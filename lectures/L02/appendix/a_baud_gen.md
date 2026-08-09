# Appendix A

## Designing `baud_gen.vhd`
A UART has no clock line. The transmitter and the receiver each keep their own time and agree only
on a number: the baud rate, the number of bits sent per second. Everything in this peripheral that
has to happen "once per bit" is paced from a single enable pulse, and `baud_gen` is what produces
it.

It does not produce one pulse per bit, though; it produces sixteen. The receiver you will build in
L03 cannot see where a bit begins, so it samples the line sixteen times per bit and picks the middle
sample (Appendix B of L03 works through that sampling). For the transmitter and the receiver to
share one time base, that time base has to tick at the finer, sixteen-times rate; the transmitter
simply counts sixteen ticks per bit. So `baud_gen` divides the 50 MHz system clock down to `16 *
baud`, and every other datapath block treats one `tick` as "one sixteenth of a bit has passed".

---

### Interface

![Module `baud_gen`](./images/baud_gen.png)

| Port / generic | Dir | Type | Meaning |
|---|---|---|---|
| `clock`      | in  | `std_logic`              | 50 MHz system clock. |
| `reset_s2_n` | in  | `std_logic`              | Active-low synchronized reset. |
| `div`        | in  | `natural range 1 to 65535` | Clocks per tick: `div = clock / (16 * baud)`. |
| `tick`       | out | `std_logic`              | One-cycle pulse every `div` clocks. |

`baud_gen_tb` binds these ports positionally, as everything in this course does, so the order and
types above must match exactly. `div` is a plain `natural`, not a vector: the register bank (L04)
holds the value as `BAUD_DIV` and hands it over already converted, so this block never touches a
`std_logic_vector` or `numeric_std`.

`div` is expected to be at least 1. The formula gives, for a 50 MHz clock: `div = 27` for 115200
baud, `326` for 9600. The testbench uses `div = 4` so a tick is only four clocks apart and the
simulation is short.

---

### Behaviour
One counter, one comparison:
* On system reset (`reset_s2_n` is low):
    * `tick` goes low.
    * The counter is reset to zero.
* On each rising edge of `clock`, while not in reset:
    * If the counter has reached `div - 1`:
        * `tick` goes high for this one cycle.
        * The counter is reset to zero.
    * If the counter hasn't reached `div - 1`:
        * `tick` stays low.
        * The counter is incremented.

So `tick` is high for exactly one clock in every `div`, and the mean tick rate is `clock / div`.
That is `16 * baud` only to within the rounding of `div`, which is an integer: at 115200 the exact
divider is 27.126, so `div = 27` runs about 0.47% fast. That margin is what the receiver's mid-bit
sampling in L03 is there to absorb.

Two details are worth getting right. The first is that **the comparison is `counter >= div - 1`, not
`counter = div - 1`**. With a stable `div` the two behave identically, since the counter reloads the
instant it reaches the threshold and never passes it. The `>=` form matters only at the edges: if
`div` were ever 0 the equality test would never fire and the counter would run free until it
overflowed its range, but `>=` catches it and simply ticks every cycle. It also means a `div` changed
mid-count is corrected on the next edge rather than after a wrap. Robustness for one character of
typing.

The second is that **the reset is asserted asynchronously**. `reset_s2_n` sits in the process's
sensitivity list, so the moment it goes low the counter clears and `tick` drops, with no clock edge
needed. That is the house style for every block here, provided and student-written alike. It is safe
precisely because `reset_s2_n` has *already* been synchronized: `uart_top` runs the raw `reset_n`
through the provided `reset_sync` once (L01 Appendix B), so the release is lined up with the clock
before any block sees it.

`tick` is a registered output, so it is glitch-free and one clock wide, which is exactly what a
downstream "count sixteen of these" expects.

---

### What the testbench pins down
`baud_gen_tb` drives `div = 4`, releases reset, then finds the first `tick` and measures the gap to
each of the next three. Every gap must be exactly four clocks, and a tick that arrives early or late
fails with the measured count in the message.

That is the whole contract: a tick every `div` clocks, steadily. The testbench does not check the
`16 * baud` arithmetic, because that lives in the *value* of `div`, which the register bank
supplies; `baud_gen` only has to divide by whatever number it is given.

---

### Where it fits
`baud_gen` sits at the root of the datapath. Its single `tick` feeds the transmitter you build
next in this lecture and the receiver in L03; both count sixteen ticks to a bit, so both stay
locked to the same time base without any handshake between them. In `uart_top` (L01) its `div`
comes from the `BAUD_DIV` register, so software sets the baud rate by writing one number.

---

### What's ahead
[Appendix B](./b_uart_tx.md) builds `uart_tx`, the transmitter. It takes the `tick` you just
produced and turns a byte into a framed serial waveform on the `tx` line.

---

