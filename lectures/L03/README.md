# L03 - The Receiver & the FIFO

## Agenda
Receiving is the hard direction, and this lecture is about why. We cover:
* **Oversampling**: the receiver watches `rx` at `16 x baud` rather than clocking on it, detecting
  the start-bit edge and then sampling each bit at its midpoint, tick 8 of 16.
* **The synchronizer**: before any of that logic can run, the asynchronous `rx` input has to pass
  through a two-flop synchronizer, `sync`, instantiated in `uart_top` so the crossing happens in the
  module that owns the pin. This is the metastability lesson from Digital Design with VHDL, reused
  here on a genuinely asynchronous input.
* **The error family**: what framing, parity and overrun each mean, and when each can be detected.
  The receiver you build here surfaces a framing error as a one-cycle pulse for the register bank to
  latch in L04; parity is left as an extension, and overrun is not something the receiver can judge
  at all, so it belongs to L04.
* **A small synchronous FIFO** (`fifo.vhd`), the buffer the register bank will need two of in L04.
  It is independent of the receiver, and building it here keeps L04 down to one module.
* **Live-coding `sync.vhd`, `uart_rx.vhd` and `fifo.vhd`**, each verified against its provided
  testbench.

---

## Objectives
After this lecture, participants should be able to:
* **Explain why an asynchronous input sampled directly can violate setup and hold**, and place a
  two-flop synchronizer correctly.
* **Explain why sampling at mid-bit, tick 8 of 16, maximizes margin against a baud mismatch**, and
  implement start-bit detection along with mid-bit sampling.
* **Detect a framing error**, emitting it as a clean single-cycle pulse alongside `valid`, and
  explain why parity is a natural extension of the same sampling loop while overrun is not the
  receiver's question to answer at all, but the register bank's in L04.
* **Build a synchronous FIFO** with a look-then-advance read, and explain why that split is what
  lets L04 keep `RX_DATA` a pure read.

---

## Prerequisites
This lecture builds on L01, which produced the `uart_top` skeleton `uart_rx` is instantiated into,
and on L02, which produced the baud generator and the frame format; the receiver reuses the same
`16 x baud` tick rather than generating its own. From Digital Design with VHDL it assumes
metastability and the two-flop synchronizer. Before the lecture, read the **Register Semantics**
notes on the three error flags in the [protocol spec](../../protocol/uart_register_protocol.md),
since L03 produces the pulses that L04 latches.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_sync.md) for `sync`, [Appendix B](./appendix/b_uart_rx.md) for
`uart_rx`, and [Appendix C](./appendix/c_fifo.md) for `fifo`; these are the specifications you build
the three modules from. Then read the provided testbenches, [`sync_tb.vhd`](../../hw/sync_tb.vhd),
[`uart_rx_tb.vhd`](../../hw/uart_rx_tb.vhd) and [`fifo_tb.vhd`](../../hw/fifo_tb.vhd). The receiver
bench has three cases, and each case comment names what it expects: a clean frame that must produce
exactly one `valid` byte and no error, a frame with a low stop bit that must raise `frame_err` and
produce no byte at all, and a break - the line held low for longer than a frame - that must produce
framing errors and no byte at all, on the way in or on recovery.

### During the Lecture
We live-code `sync.vhd`, then `uart_rx.vhd` with its start-bit detection and mid-bit sampling,
running each against its testbench:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd sync.vhd uart_rx.vhd sync_tb.vhd uart_rx_tb.vhd
ghdl -e --std=93 uart_rx_tb && ghdl -r --std=93 uart_rx_tb --assert-level=error
```

Then we instantiate `uart_rx` into `uart_top`, which brings `sync` with it; the RX datapath now
feeds the register bus, which the register bank answers in L04. `fifo` is specified in Appendix C
and built in the exercises; it is not instantiated yet either, since it waits for the bank that owns
it.

**The 60 minutes.** We type `sync`, which is four lines of logic and a long discussion, and
then the half of `uart_rx` that is genuinely hard: detecting the start edge and sampling at tick 8
of 16. The rest of the receiver, the data-bit loop and the stop-bit check, follows the same pattern
once that is clear. `fifo` is not typed live at all. It is the most conventional block in the
course, fully specified in Appendix C, and it is exactly the kind of thing that should cost you an
evening rather than a session.

### After the Lecture
Work through the [exercises](./appendix/d_exercises.md): build `sync`, `uart_rx` and `fifo`
from Appendices A, B and C, instantiate the receiver into `uart_top`, then reason about why overrun
detection belongs to the register bank rather than the receiver.

---

## Evaluation
* Why must `rx` pass through `sync` before any logic looks at it, and what can go wrong without it?
* The receiver samples at tick 8 of 16: as the transmitter's baud drifts from the receiver's, what
  breaks first, the early bits or the late ones, and why?
* What is an overrun, why can the receiver not detect one on its own, and which block would have to
  do it instead?

---

## Next Lecture
Ports become registers: sticky `STATUS` bits, a write-triggered TX push, the read-then-pop RX path
over the two FIFOs you just built, and completing `uart_top` behind the provided SPI transport, so
the system testbench finally runs.

---

