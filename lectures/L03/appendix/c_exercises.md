# Appendix C

## Exercises
Exercise 1 reinforces [Appendix A](./a_sync.md) and Exercise 2 [Appendix B](./b_uart_rx.md). Design
each module from the specification in its own appendix and check it with the provided testbench, run
from `hw/` (see [`hw/README.md`](../../../hw/README.md)). The FIFO, the two instantiations that put
the receive path into `uart_top`, and the overrun question belong to
[L04](../../L04/appendix/b_exercises.md), not to this lecture.

---

## Exercise 1 - `sync`
**a)** Write your own `sync.vhd` from Appendix A's specification and run its testbench:

```bash
cd hw
ghdl -a --std=93 sync.vhd sync_tb.vhd
ghdl -e --std=93 sync_tb
ghdl -r --std=93 sync_tb --assert-level=error
```

Note that no package appears in that first line: `sync` reads none, which is part of what makes it
reusable.

**b)** Delete one of the two flip flops, leaving a single register, and re-run. Which check fails,
and what does its message tell you? Put it back. Why would this bug pass every *other* simulation
in the course if this one testbench did not exist?

**c)** `sync` clears on `reset_s2_n`, and the testbench asserts it *between* two clock edges and
requires the output to clear before the next one. Change your reset to a synchronous one, tested
inside `if rising_edge(clock)`, and re-run. Which check fails, and what is the message? Put it back,
then say why the assertion has to be asynchronous while the *release* does not need to be, given
where `reset_s2_n` comes from.

**d)** `sync` takes `reset_s2_n`, the already-synchronized reset, as an input. Explain why that one
fact makes it impossible for `sync` to be the module that produces `reset_s2_n`, and why
`reset_sync` therefore exists as a separate provided block even though both are two flops in
series.

**e)** `uart_top` uses `sync` at `COUNT = 1`. Two bits of a `COUNT = 8` instance change on the same
edge; explain why `sync_out` may show one bit's new value and the other's old one for a clock, why
that is not a bug in `sync`, and why it would matter if those eight bits were a counter read across
clock domains rather than eight unrelated pins.

---

## Exercise 2 - `uart_rx`
**a)** Write your own `uart_rx.vhd` from Appendix B's specification and run its testbench:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd uart_rx.vhd uart_rx_tb.vhd
ghdl -e --std=93 uart_rx_tb
ghdl -r --std=93 uart_rx_tb --assert-level=error
```

`uart_def.vhd` comes first because `uart_rx_tb` names bits through the package. `sync.vhd` is not on
that line at all: `uart_rx` reads `rx_s2`, the already-synchronized line, and instantiates nothing.
The crossing belongs one level up, in `uart_top`, which is where
[L04 Exercise 2](../../L04/appendix/b_exercises.md) puts it.

**b)** The receiver samples each bit at tick 8 of 16. Suppose the transmitter's baud rate is a few
percent faster than the receiver's, so the receiver's ticks are slightly long. Which end of the
byte drifts furthest from the bit centre, the first data bit or the stop bit, and why? Roughly how
much faster could the transmitter run before the stop-bit sample landed outside its bit?

**c)** The `STATE_START` state re-checks `rx_s2` at tick 8 before committing to a frame. Remove
that check (go straight from the falling edge to `STATE_DATA`) and describe what a single-tick
glitch on an idle line would now produce. Which real-world condition makes this more than a
theoretical worry?

**d)** Trace the store `frame(bit_idx) <= rx_s2` for the byte `0x53` (`0101_0011`) sent least
significant first. Write the eight received bits in the order they arrive, name the index each one
lands in, and show that after eight bits `frame` holds `0x53`. Then: what would `data_out` read if
`bit_idx` counted **down** from 7 instead of up from 0, and what is the relationship between that
byte and the one that was sent?

---
