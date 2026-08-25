# L03 - The Synchronizer & the Receiver

## Agenda
Receiving is the hard direction, and this lecture is about why. We cover:
* **The synchronizer**: before any receive logic can run, the asynchronous `rx` input has to pass
  through a two-flop synchronizer, `sync`, which `uart_top` will instantiate on the pin so the
  crossing happens in the module that owns it. This is the metastability lesson from Digital Design
  with VHDL, reused here on a genuinely asynchronous input.
* **Oversampling**: the receiver watches `rx` at `16 x baud` rather than clocking on it, detecting
  the start-bit edge and then sampling each bit at its midpoint, tick 8 of 16.
* **Leaving idle on an edge, not a level**: one flip-flop of history for `rx_s2`, and why it is the
  difference between a receiver that works on clean data and one that survives a cable being
  unplugged.
* **The error family**: what framing, parity and overrun each mean, and when each can be detected.
  The receiver you build here surfaces a framing error as a one-cycle pulse for the register bank to
  latch in L05; parity is left as an extension, and overrun is not something the receiver can judge
  at all, so it belongs to L04's closing discussion and to L05.
* **Live-coding `sync.vhd` and `uart_rx.vhd`**, each verified against its provided testbench.

The buffer the register bank needs, and the two instantiations that put this lecture's modules into
`uart_top`, are L04's; this hour is the receiver and nothing else.

---

## Objectives
After this lecture, participants should be able to:
* **Explain why an asynchronous input sampled directly can violate setup and hold**, and place a
  two-flop synchronizer correctly.
* **Explain why sampling at mid-bit, tick 8 of 16, maximizes margin against a baud mismatch**, and
  implement start-bit detection along with mid-bit sampling.
* **Explain why the receiver leaves idle on a falling edge rather than a low level**, and what a
  break does to a receiver that tests the level instead.
* **Detect a framing error**, emitting it as a clean single-cycle pulse alongside `valid`, and
  explain why parity is a natural extension of the same sampling loop while overrun is not the
  receiver's question to answer at all.

---

## Prerequisites
This lecture builds on L01, which produced the `uart_top` skeleton the receive path will be
instantiated into in L04, and on L02, which produced the baud generator and the frame format; the
receiver reuses the same `16 x baud` tick rather than generating its own. From Digital Design with
VHDL it assumes metastability and the two-flop synchronizer. Before the lecture, read the **Register
Semantics** notes on the three error flags in the [protocol
spec](../../protocol/uart_register_protocol.md), since L03 produces the pulses that L05 latches.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_sync.md) for `sync` and [Appendix B](./appendix/b_uart_rx.md) for
`uart_rx`; these are the specifications you build the two modules from. Then read the provided
testbenches, [`sync_tb.vhd`](../../hw/sync_tb.vhd) and [`uart_rx_tb.vhd`](../../hw/uart_rx_tb.vhd).
The receiver bench has three cases, and each case comment names what it expects: a clean frame that
must produce exactly one `valid` byte and no error, a frame with a low stop bit that must raise
`frame_err` and produce no byte at all, and a break - the line held low for longer than a frame -
that must produce framing errors and no byte at all, on the way in or on recovery.

### During the Lecture
We live-code `sync.vhd`, then `uart_rx.vhd` with its start-bit detection and mid-bit sampling,
running each against its testbench:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd sync.vhd uart_rx.vhd sync_tb.vhd uart_rx_tb.vhd
ghdl -e --std=93 uart_rx_tb && ghdl -r --std=93 uart_rx_tb --assert-level=error
```

Neither module is instantiated yet. `uart_top` gains both in L04, together with the FIFO the
register bank will own, which is why this hour can stay on the one hard idea.

**The 60 minutes.** We type `sync`, which is four lines of logic and a long discussion, and then
the half of `uart_rx` that is genuinely hard: detecting the start edge and sampling at tick 8 of 16.
The rest of the receiver, the data-bit loop and the stop-bit check, follows the same pattern once
that is clear, and it is the exercise. What the hour buys by leaving the FIFO to L04 is time on the
break case: why idle is left on an edge rather than a level, and what a level test does to the frame
still in flight when the break ends.

### After the Lecture
Work through the [exercises](./appendix/c_exercises.md): build `sync` and `uart_rx` from Appendices
A and B, run both testbenches, and reason about sampling margin, glitch rejection, and the
bit order the shift produces.

---

## Evaluation
* Why must `rx` pass through `sync` before any logic looks at it, and what can go wrong without it?
* The receiver samples at tick 8 of 16: as the transmitter's baud drifts from the receiver's, what
  breaks first, the early bits or the late ones, and why?
* Idle is left on a falling edge rather than on a low level. Which of the three testbench cases
  fails if you test the level instead, and what does the receiver deliver that it should not?

---

## Next Lecture
The buffer the register bank will need two of: a small synchronous FIFO with a look-then-advance
read. Then the receive path goes into `uart_top`, `sync` on the pin and `uart_rx` behind it, and
we work out why overrun is not a question the receiver can answer.

---
