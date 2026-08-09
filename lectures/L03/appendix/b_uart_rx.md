# Appendix B

## Designing `uart_rx.vhd`
Receiving is harder than transmitting for one reason: the transmitter chooses when each bit begins,
and the receiver has to *find out*. There is no clock on the wire, only the line itself, idle high,
falling low to start a frame. The receiver has to notice that falling edge, then read eight data
bits and a stop bit whose timing it can only infer from the baud rate it was told.

The technique is **oversampling**. The receiver runs at the same `16 * baud` tick as the
transmitter (from `baud_gen`), so there are sixteen ticks per bit. It does not try to sample on the
bit edge, where the line is changing; it aims for the **middle** of each bit, tick 8 of 16,
where the level is settled and a small timing error either way is harmless. Sampling at the centre
is the single idea that makes an asynchronous line readable.

---

### Interface

![Module `uart_rx`](./images/uart_rx.png)

| Port | Dir | Type | Meaning |
|---|---|---|---|
| `clock`      | in  | `std_logic`                    | 50 MHz system clock. |
| `reset_s2_n` | in  | `std_logic`                    | Active-low synchronized reset. |
| `baud_tick`  | in  | `std_logic`                    | The 16x oversample tick from `baud_gen`. |
| `rx_s2`      | in  | `std_logic`                    | The serial input, already synchronized. |
| `data_out`   | out | `std_logic_vector(7 downto 0)` | The received byte. |
| `valid`      | out | `std_logic`                    | A one-cycle pulse: `data_out` is fresh. |
| `frame_err`  | out | `std_logic`                    | A one-cycle pulse: the stop bit was not high. |

`uart_rx_tb` binds these positionally. Note what this port is **not**: it is not the raw pin. The
two-flop synchronizer that cleans up `rx` lives one level up, in `uart_top`, which instantiates
`sync` (Appendix A) on the pin and passes the result down as `rx_s2`. By the time the receiver sees
the line it has already been resynchronized to the system clock, so every process in here treats it
as an ordinary synchronous input and samples it directly.

Putting the synchronizer in the top rather than inside the receiver keeps the responsibility where
the asynchronous boundary actually is. `uart_top` owns the pins, so it owns the crossing; `uart_rx`
is then a purely synchronous design, which is easier both to reason about and to test.

---

### Behaviour
Four states, `STATE_IDLE`, `STATE_START`, `STATE_DATA` and `STATE_STOP`, and two counters between
them: `ticks` counts 0 to 15 within one bit, and `bit_idx` counts 0 to 7 across the data bits. Apart
from the output defaults, the whole process sits inside `if baud_tick = '1'`, so the receiver
advances in oversample periods rather than clock cycles.

* On reset (`reset_s2_n` is low):
    * `data_out` is cleared, and `valid` and `frame_err` go low.
    * The state returns to `STATE_IDLE`.
    * `frame`, `bit_idx`, `ticks` and `sample_data` are cleared.
    * `rx_prev` is set to `'1'`, the idle level, so the first tick after reset cannot look like a
      falling edge.
* On each rising edge of `clock`, while not in reset:
    * `data_out` is cleared and `valid` and `frame_err` go low, so any pulse from the previous cycle
      lasts exactly one clock.
    * If `baud_tick = '1'`, the oversample counter runs first, ahead of the state machine:
        * If `ticks` has reached 15, a whole bit period has passed: raise `sample_data` and clear
          `ticks`.
        * If `ticks` has not reached 15: lower `sample_data` and increment `ticks`.
    * Then, on that same tick, in **`STATE_IDLE`**:
        * If `rx_s2` has just **fallen**, low on this tick and high on the one before it, a start
          bit may be beginning:
            * Clear `ticks`, restarting the count from this edge.
            * Move to `STATE_START`.
    * In **`STATE_START`**:
        * If `sample_start_bit = '1'`, that is `ticks` has reached 8, half a bit on from the edge:
            * If `rx_s2` is still low the start is genuine: clear `ticks` and move to `STATE_DATA`.
            * If `rx_s2` has gone high the low was a glitch rather than a start, so return to
              `STATE_IDLE`. That mid-bit re-check is what rejects noise on an idle line.
    * In **`STATE_DATA`**:
        * If `sample_data = '1'`, a full bit has passed since the last sample:
            * Store the line into the frame: `frame(bit_idx) <= rx_s2`.
            * If `bit_idx` has reached 7, the eighth and last data bit is in:
                * Clear `ticks` and `bit_idx`, and move to `STATE_STOP`.
            * If `bit_idx` has not reached 7:
                * Increment `bit_idx`, moving to the next bit.
    * In **`STATE_STOP`**:
        * If `sample_data = '1'`, a full bit has passed since the last data bit:
            * If `rx_s2` is high the stop bit is where it should be, so the frame is good: present
              `frame` on `data_out` and raise `valid` for this one cycle.
            * If `rx_s2` is low the framing is broken: raise `frame_err` for this one cycle instead,
              clear `frame`, and drop the byte.
            * Either way, return to `STATE_IDLE`.
    * Last on the tick, after the state machine has read it, `rx_prev` takes the current `rx_s2`.
      Updating it last is what makes the comparison above "this tick against the previous one"
      rather than a signal compared with itself.

### Why idle waits for an edge, not a level
Keeping one tick of history for `rx_s2` costs a single flip-flop, and leaving idle only on the
high-to-low transition is what that flip-flop buys. Testing the level instead, "if `rx_s2` is low,
start a frame", passes every frame `uart_rx_tb` sends and fails on the one case that matters.

Consider a **break**: the line held low far longer than a frame, which is what a transmitter losing
power or a cable coming loose looks like. With a level test the receiver re-arms the moment the
previous frame's stop bit is judged, so it spends the break marching through back-to-back all-zero
frames. Each of those ends on a low stop bit and is correctly rejected as a framing error, and that
part is fine. The problem is the frame still in flight when the break *ends*: its stop bit is
sampled after the line has returned high, so it is a well-formed frame as far as the receiver can
tell, and a byte assembled out of nothing is pushed into the FIFO as real data.

With an edge test there is no second falling edge until the line has gone high again, so no frame is
ever in flight across that boundary. One flip-flop, and it is the difference between a receiver that
works on clean data and one that survives a cable being unplugged.

`sample_start_bit` is not part of that process at all. It is one concurrent line, high whenever the
tick counter sits half a bit past the edge that restarted it:

```vhdl
sample_start_bit <= '1' when ticks = HALF_TICKS else '0';
```

Two details in the process are easy to miss. The counter block and the state machine both assign
`ticks`, and the counter block comes first, so wherever a state clears `ticks` that clear is what
takes effect: VHDL gives the last assignment in a process the final say. And `sample_data` is a
registered flag rather than a comparison, so it is raised on the tick where `ticks` wraps and acted
on at the next one. Because the state machine runs only on a `baud_tick`, it still fires once per
bit rather than once for every clock in the tick.

Between them those two details also decide *where* in each bit the sample lands, and it is not
exactly tick 8. Three things each cost a tick: the falling edge is only noticed at the next
`baud_tick`; `ticks` is compared before it is incremented; and every `ticks <= 0` on a state change
spends one more. So the start-bit re-check arrives nine ticks after the edge rather than eight, the
first data sample seventeen ticks after that re-check rather than sixteen, and the stop bit
seventeen after the last data bit, while data bit to data bit is exactly sixteen. Against the frame
`uart_rx_tb` sends, that puts the start-bit check two ticks past the centre of its bit, each data
bit three, and the stop bit four.

The spacing between data bits is right, so that offset is fixed rather than accumulating across the
byte, and a sample three ticks late still has five ticks of settled line ahead of it rather than
eight. The receiver works, and the bench passes, but it begins with roughly half the trailing margin
the ideal tick-8 sample would have. That is worth holding on to for the margin question in
[Appendix D](./d_exercises.md): the budget a real receiver spends on baud mismatch is whatever the
sampling phase has not already spent.

Walking `bit_idx` from 0 upward and storing with `frame(bit_idx) <= rx_s2` puts the first-received
bit in bit 0, which is **least significant first**, the order the transmitter sent them in, so
`data_out` reads out as the byte that was sent.

`valid` and `frame_err` are one-cycle pulses, so `uart_top` can turn a `valid` straight into a
FIFO push and latch a `frame_err` into the `ERROR_FLAGS` register (L04). Both default low every
cycle and rise for exactly one clock at the stop-bit sample.

Parity and overrun are deliberately absent here. Parity would be another mid-bit sample between the
last data bit and the stop bit, gated by `CTRL`; overrun (a new byte arriving before the last was
read) is not something the receiver can judge, because it does not know whether anyone has read the
byte. That belongs to the register bank, where the RX FIFO's full flag answers it (L04).

---

### What the testbench pins down
`uart_rx_tb` drives framed bytes onto `rx` at sixteen ticks per bit and checks three cases. A clean
byte must arrive on `data_out` with `valid` and no `frame_err`, and with the right value, which is
what pins down the least-significant-first shift. A byte whose stop bit is driven low must raise
`frame_err` and produce no `valid` byte. And a **break**, the line held low for longer than a frame
and then released, must produce framing errors and no byte at all, which is the case discussed
above and the only one that requires leaving idle on an edge rather than a level.

The clean byte is `0x53`, and the choice matters for the same reason it does in
[L02](../../L02/appendix/b_uart_tx.md): `0x53` reversed is `0xCA`, so a receiver that walked
`bit_idx` the wrong way would deliver a visibly different byte and fail. A **bit-reversal
palindrome** such as `0xA5` would be delivered unchanged by a receiver storing its bits backwards,
and the check would pass on a broken design.

It counts the `valid` and `frame_err` pulses with a small monitor process rather than racing the
one-cycle strobes, which is worth copying whenever a testbench has to catch a pulse.

---

### Where it fits
`uart_rx` is the input half of the datapath. In `uart_top` (L01) its `valid` and `data_out` become
`uart_regs`' `rx_push` and `rx_byte`, so the bank pushes the received byte into the RX FIFO it owns,
and its `frame_err` feeds the same bank's error latch. Its `rx` pin is the peripheral's serial
input, looped back from `tx` in the system testbench so a sent byte comes straight back.

---

### What's ahead
[Appendix D](./d_exercises.md) is the exercises: build `sync`, `uart_rx` and `fifo`, run their
testbenches, and reason about oversampling margin, glitch rejection, and where overrun really lives.

---

