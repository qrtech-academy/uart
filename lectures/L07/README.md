# L07 - The Real Transport, and Both Toolchains

## Agenda
This is where the stub gives way to real hardware.

* **The AVR's own SPI peripheral**: `SPCR`, `SPSR` and `SPDR` as genuine memory-mapped `volatile`
  registers, configured as an SPI master at f_osc/16 = 1 MHz, mode 0, MSB first, matching [Part 3 of
  the spec](../../protocol/uart_register_protocol.md).
* **`AvrSpi` on top of it**, implementing the same `driver::transport::Interface` seam that L06's
  `driver::transport::Stub` did, only now clocking real bytes. Nothing above the seam changes, which
  is the whole return on the design work in L05.
* **What a freestanding target removes**, namely the heap, exceptions, RTTI and iostreams, and what
  replaces each: static storage, return codes, virtual dispatch in place of `dynamic_cast`, and
  logging over the AVR's own hardware UART.
* **Building with avr-gcc and flashing with avrdude.**
* **The other toolchain**: synthesizing `uart_board.vhd` in Quartus, assigning pins, and programming
  the DE0-CV over USB-Blaster. Both halves of the course reach real hardware in this lecture, and
  doing the FPGA side here rather than on bring-up day means a toolchain problem surfaces while
  there is still time to solve it.

---

## Objectives
After this lecture, participants should be able to:

* **Configure the AVR SPI master registers** correctly for the transport contract, and explain each
  bit they set.
* **Implement `AvrSpi`** so that the existing driver and its host tests are reused unchanged.
* **Explain which host-side idioms do not survive a freestanding build**, and what replaces them.
* **Synthesize and program the DE0-CV**, and read a fit and timing report well enough to say whether
  the design met timing at 50 MHz.

---

## Prerequisites
This lecture needs the `driver::transport::Interface` seam from L05, which is what the new transport
implements, and the `Uart` driver and host tests from L06, which are reused here unchanged. It also
needs the finished `uart_top` from L04, passing its system testbench, because the second half of the
lecture puts that design on the FPGA. From Embedded C it assumes the AVR toolchain, avr-gcc and
avrdude, and register-level programming; from Modern Embedded C++, the `volatile` semantics of
memory-mapped registers. Install **Quartus Prime Lite** before the lecture: it is a multi-gigabyte
download, and it is the one tool the course has not needed until now.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_avr_transport.md) for the SPI peripheral and `AvrSpi`, and
[Appendix B](./appendix/b_freestanding.md) for the freestanding target and the toolchain. Alongside
them, read the ATmega328P datasheet's SPI section covering `SPCR`, `SPSR` and `SPDR`, and the
provided `avr/` runtime and Makefile under [`fw/`](../../fw/README.md).

### During the Lecture
We live-code `AvrSpi`, confirm the host tests still pass unchanged with `make build-cpp`, then
cross-compile and flash a minimal bring-up `main` to show the toolchain end to end:

```bash
make -C fw/avr flash # avr-gcc + avrdude; see fw/README.md.
```

Then the same journey on the other chip, demonstrated rather than typed: we synthesize the
`uart_top` finished in L04 through the provided `uart_board.vhd` wrapper, read the fit and timing
report, and program the DE0-CV over USB-Blaster. With `tx` jumpered to `rx` the peripheral echoes
itself, which is the loopback `uart_top_tb` ran in simulation, now at a real 50 MHz.

**The 60 minutes.** `AvrSpi` is about forty lines and we type all of it, going through `SPCR` bit by
bit, because a wrong bit here is a bug you would otherwise meet on a logic analyzer at the bench.
That leaves room for the Quartus flow, which is demonstrated rather than typed: compile, read the
fit and timing report, program the board, and jumper `tx` to `rx` to watch the peripheral echo
itself. The freestanding `main`, the UART logging and synthesizing your own `uart_top` are the
exercises.

### After the Lecture
Work through the [exercises](./appendix/c_exercises.md): implement `AvrSpi` and the freestanding
bring-up `main`, add UART-based logging over the AVR's own hardware UART, and work out one
`readReg()` round trip against the 1 MHz SCK budget - measuring it on a logic analyzer if you have
one. Synthesize and program your own `uart_top` as well, so that both chips are running your code
before the bench session.

---

## Evaluation
* Which idiom from the host build fails to compile freestanding, and how does L07 replace it?
* The AVR SPI runs at 1 MHz: which prescaler setting produces it from a 16 MHz clock, and what
  actually limits SCK on this bench, given that the FPGA slave could keep up with considerably more?
* If `SPDR` is read a cycle too early, before `SPIF` is set, what value comes back, and how does the
  transport avoid it?

---

## Next Lecture
Both halves on the bench: two links, a level shifter, and a bring-up ladder that ends with an
echo application driven end to end.

---

