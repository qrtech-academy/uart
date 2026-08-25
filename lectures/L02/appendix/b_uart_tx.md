# Appendix B

## Designing `uart_tx.vhd`
The transmitter turns one byte into the waveform a UART line carries: a low **start bit**, then the
eight data bits **least significant first**, then a high **stop bit**, with the line sitting **idle
high** between frames. That default framing is called 8N1 (8 data bits, No parity, 1 stop bit), and
it is the only framing this transmitter produces; parity and a second stop bit are left as an
exercise.

The transmitter owns no time of its own. It counts the `tick`s from `baud_gen`, sixteen to a bit,
and changes the line only on bit boundaries. So the whole of its timing is "hold this bit for
sixteen ticks, then move to the next".

---

### Interface

![Module `uart_tx`](./images/uart_tx.png)

| Port | Dir | Type | Meaning |
|---|---|---|---|
| `clock`      | in  | `std_logic`                    | 50 MHz system clock. |
| `reset_s2_n` | in  | `std_logic`                    | Active-low synchronized reset. |
| `baud_tick`  | in  | `std_logic`                    | The 16x oversample tick from `baud_gen`. |
| `start`      | in  | `std_logic`                    | A one-cycle pulse: latch `data` and begin sending. |
| `data`       | in  | `std_logic_vector(7 downto 0)` | The byte to send. |
| `tx`         | out | `std_logic`                    | The serial line, idle high. |
| `busy`       | out | `std_logic`                    | High for the whole frame. |
| `done`       | out | `std_logic`                    | A one-cycle pulse as the frame completes. |

`uart_tx_tb` binds these ports positionally, as everything in this course does, so the order and
types above must match exactly. `start` is a load command, not a level: it is looked at only while
the transmitter is idle, so holding it high does not re-send. In `uart_top` (L01) the TX feeder
pulses `start` and pops the FIFO in the same cycle, so `data` is the FIFO's front byte.

---

### The frame
Build the whole frame once, as a 10-bit vector, then just index it. This is the trick that keeps the
rest of the module short:

```vhdl
frame <= STOP_BIT & data & START_BIT;   -- '1' & data(7 downto 0) & '0'
```

Concatenation puts the leftmost item in the highest bits, so that vector reads:

| `frame` index | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|
| carries | stop | `data(7)` | `data(6)` | `data(5)` | `data(4)` | `data(3)` | `data(2)` | `data(1)` | `data(0)` | start |
| value | `'1'` | | | | | | | | | `'0'` |

Read it from index **0 upward** and you get exactly the wire order: the start bit, then `data(0)`
through `data(7)` least significant first, then the stop bit. So the transmitter never has to think
about bit order again. It drives `tx <= frame(bit_idx)` and walks `bit_idx` from 0 to 9.

---

### Behaviour
Two states, `STATE_IDLE` and `STATE_SEND`, and two counters between them: `ticks` counts 0 to 15
within one bit, and `bit_idx` counts 0 to 9 across the frame.

* On reset (`reset_s2_n` is low):
    * `tx` goes high, the idle level.
    * `done` goes low and the state returns to `STATE_IDLE`.
    * `frame`, `bit_idx` and `ticks` are cleared.
* On each rising edge of `clock`, while not in reset:
    * `done` goes low, so any pulse from the previous cycle lasts exactly one clock.
    * In **`STATE_IDLE`**:
        * `tx` is held high.
        * If `start = '1'`:
            * Build `frame` from `data`, as above.
            * Drive `tx` low, beginning the start bit.
            * Move to `STATE_SEND`.
    * In **`STATE_SEND`**:
        * Drive `tx <= frame(bit_idx)`, the bit currently being sent.
        * If `baud_tick = '1'`:
            * If `ticks` has reached 15, this bit is finished:
                * Clear `ticks`.
                * If `bit_idx` has reached 9, the stop bit is finished:
                    * Raise `done` for this one cycle.
                    * Clear `bit_idx` and return to `STATE_IDLE`.
                * If `bit_idx` has not reached 9:
                    * Increment `bit_idx`, moving to the next bit.
            * If `ticks` has not reached 15:
                * Increment `ticks`, holding the current bit.

`busy` is not part of that process at all. It is one concurrent line, high whenever the state
machine is sending:

```vhdl
busy <= '1' when state = STATE_SEND else '0';
```

Three details are worth getting right.

The first is that **`ticks` and `bit_idx` advance only on a `baud_tick`**. Every other clock edge in
`STATE_SEND` does nothing but re-drive `tx` with the same bit. At 115200 baud `BAUD_DIV` is 27, so
that is 26 idle edges for every one that counts, which is the point: the transmitter is paced by
`baud_gen`, not by the system clock.

The second is that **`done` is cleared at the top of every clock edge and set only in the single
cycle the frame ends**. Writing the default first and letting the specific case override it is what
guarantees a one-cycle pulse with no extra counter. The two status outputs then carry different
information. `busy` is a *level* covering the whole frame, and is what the feeder in `uart_top`
watches so it does not load another byte mid-frame. `done` is an *event*, useful for counting frames
or raising an interrupt, and it is not what moves the next byte along.

The third is that **the frame is captured on `start`**, so the caller may change `data` on the very
next cycle. The byte in flight lives in `frame`, not in the caller's register.

---

### What the testbench pins down
`uart_tx_tb` generates `baud_tick` locally at one pulse per four clocks, so a bit is 64 clocks and
the frame simulates quickly. It checks that:
* `tx` **idles high** before anything is sent.
* `tx` **goes low within two bit periods** of `start`. This catches a transmitter that never leaves
  the idle state; without it the bench would wait for a falling edge that never comes, and hang.
* The **start bit is low** at its centre.
* The **eight data bits match `0x53`, least significant first**, sampled a full bit apart. This is
  the check that catches a transmitter sending MSB-first.
* The **stop bit is high**.

Sampling at bit centres rather than edges is the same discipline the receiver uses in L03, and it is
why a one-tick timing slip does not fail the test while a wrong bit order does.

The **choice of `0x53` is not arbitrary**, and it is worth knowing why before you write a testbench
of your own. `0x53` is `0101_0011`, and reversed it is `1100_1010`, or `0xCA` - a different byte, so
a frame packed most significant first fails on the very first data bit. A byte that reads the same
backwards would not test the ordering at all: `0xA5` is `1010_0101` either way round, so both
packings put exactly the same ten levels on the line and the bench passes on both. Sixteen of the
256 bytes are such **bit-reversal palindromes** - `0xA5`, `0x3C` and `0x5A` among them - and
choosing one of them turns a real check into a decoration. Exercise 2 makes you demonstrate it.

Note what the bench does **not** check. `busy` and `done` are bound but never asserted on, so a
`busy` that rises one cycle late still passes here. That bug surfaces only in L05, as a TX feeder
that loads two bytes where it should have loaded one.

---

### Where it fits
`uart_tx` is the output half of the datapath. In `uart_top` (L01) its `data` comes from the TX FIFO
and its `start` and `busy` drive the feeder that empties that FIFO one byte at a time; its `tx` pin
leaves the FPGA as the peripheral's serial output. It shares `baud_gen`'s single `tick` with the
receiver built in L03, which is what keeps the two halves on one time base.

---

### What's ahead
[Appendix C](./c_exercises.md) is the exercises: build `baud_gen` and `uart_tx` from these two
appendices, run their testbenches, and probe the design decisions the tests depend on.

---

