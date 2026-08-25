# L02 - UART Framing & the Transmitter

## Agenda
This lecture works from the wire up. We cover:

* **UART framing itself**: the idle-high line, the start bit, eight data bits sent least significant
  first, optional parity, and one or two stop bits, and how a baud rate maps to a bit period. The
  [line-protocol section](../../protocol/uart_register_protocol.md) of the spec fixes the default
  8N1 frame and the `BAUD_DIV` divider taken from the 50 MHz system clock.
* **The baud-rate generator**, which emits one enable tick at `16 x baud`, so that the transmitter
  written here and the receiver written in L03 share a single time base rather than each keeping its
  own.
* **Live-coding `baud_gen.vhd` and then `uart_tx.vhd`**, each verified against its provided
  testbench.

---

## Objectives
After this lecture, participants should be able to:

* **Draw a `tx` waveform** for a given byte, baud and frame format, and mark the bit boundaries on
  it.
* **Explain why the transmitter needs a baud tick at `16 x baud`** rather than at the baud rate
  itself, given that L03's receiver oversamples.
* **Implement a transmitter state machine** that loads, shifts and frames, with correct `busy` and
  `done` timing, verified against a provided testbench.

---

## Prerequisites
This lecture follows on from L01, where `uart_def` and the `uart_top` skeleton were built; `baud_gen`
and `uart_tx` are the first two blocks you instantiate into that top. From Digital Design with VHDL
it assumes `entity` and `architecture`, clocked processes, state machines, and running a provided
self-checking testbench with GHDL. Before the lecture, read the **UART Line Protocol** section of the
[protocol spec](../../protocol/uart_register_protocol.md).

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_baud_gen.md) for `baud_gen` and [Appendix B](./appendix/b_uart_tx.md)
for `uart_tx`; these are the specifications you build the two modules from. Then read the provided
testbenches, [`baud_gen_tb.vhd`](../../hw/baud_gen_tb.vhd) and
[`uart_tx_tb.vhd`](../../hw/uart_tx_tb.vhd), which are the executable form of this lecture's contract
and whose case comments each state what a failure means. Confirm your GHDL install beforehand by
running an existing testbench from Digital Design with VHDL.

### During the Lecture
We live-code `baud_gen.vhd`, the divider and its enable tick, then the core of `uart_tx.vhd`, the
transmitter state machine, running each against its testbench as it lands:

```bash
cd hw
ghdl -a --std=93 baud_gen.vhd baud_gen_tb.vhd
ghdl -e --std=93 baud_gen_tb
ghdl -r --std=93 baud_gen_tb --assert-level=error
```

Then we instantiate both into the `uart_top` skeleton from L01, so the top now drives `tx`. The
system testbench still waits for the receiver and the register bank.

**The 60 minutes.** We type `baud_gen` in full, since it is small and the argument for `counter >=
div - 1` over `counter = div - 1` is worth the time it takes, and then the part of `uart_tx` that
carries the idea: the frame assembled as a vector, and the state machine around it. The `busy` and
`done` timing, and instantiating both blocks into `uart_top`, are left to the exercises.

### After the Lecture
Work through the [exercises](./appendix/c_exercises.md): build `baud_gen` and `uart_tx` from
Appendices A and B, instantiate them into `uart_top`, then extend the transmitter with parity and a
second stop bit.

---

## Evaluation
* Why is the line idle-high, and what does a receiver detect to know a frame has started?
* A byte is sent at 115200 baud with the 50 MHz clock: how many system cycles long is one bit, and
  what `BAUD_DIV` produces it?
* If `done` is asserted one cycle too early, which frame bit gets corrupted when the next byte is
  loaded, and why?

---

## Next Lecture
The hard direction: recovering bytes from an asynchronous line; a two-flop synchronizer on `rx`,
16x oversampling, mid-bit sampling and framing-error detection.

---

