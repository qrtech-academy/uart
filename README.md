# UART: Hardware, Driver & Integration
Repository for the course **UART: Hardware, Driver & Integration (FPGA meets MCU)**.

This is the **entry course** to the FPGA-meets-MCU pattern: build a hardware peripheral in VHDL,
write its driver in Modern C++, then integrate the two across a real chip boundary. UART is the
simplest serial peripheral there is, chosen deliberately so participants meet the *pattern*,
and the whole hardware -> driver -> integrate loop, before meeting a hard protocol. The much
larger CAN course chain later applies the same loop to a far more demanding protocol in far
greater depth; this course is where the shape is learned.

The full stack, top (application) to bottom (the wire), spans two chips joined by two serial
links. Every layer is written by the participant except the provided SPI transport:

| Layer | Runs on | Written by |
| ----- | ------- | ---------- |
| `app::EchoNode` | ATmega328P (C++) | this course |
| Driver interface | ATmega328P (C++) | this course |
| `driver::uart::Uart` | ATmega328P (C++) | this course |
| AVR SPI master (a `driver::transport::Interface`) | ATmega328P (C++) | this course |
| *SPI link: 4 wires + a 5 V ↔ 3.3 V level shifter (control plane)* | | |
| `spi_slave` → `spi_reg_bridge` | DE0-CV (VHDL) | provided (black box) |
| Register bank | DE0-CV (VHDL) | participant |
| `uart_top` (baud gen, TX, RX, FIFOs) | DE0-CV (VHDL) | participant |
| *UART link: tx/rx at 3.3 V (data plane)* | | |
| PC USB-serial terminal (or a second node) | external | — |

Note the two serial links, and that they are *not* the same protocol. The **control plane** is
SPI: the ATmega328P is the CPU, and it configures and drives the FPGA's UART peripheral by
reading and writing the peripheral's registers over SPI. The **data plane** is the UART itself:
the peripheral's own `tx`/`rx` lines carry bytes to and from the outside world. There is no soft
CPU anywhere; the processor is the real ATmega328P on the Nano.

---

## Why drive a UART over SPI when the ATmega already has one?
Because the ATmega's own UART is not the subject, the *pattern* is. Here the ATmega plays host
CPU to a memory-mapped peripheral it does not contain, reaching it across a chip boundary. That
is the real situation with FPGA and ASIC peripherals, and it is what makes the skill transfer to
the next protocol. Building a UART this way is not the efficient way to get a UART; it is the way
to learn the boundary; with a protocol simple enough that nothing about the boundary is hidden
by the protocol's own complexity.

---

## About the Course
The course covers the hardware/software boundary of an embedded system through the simplest
serial peripheral there is. Topics include:
* UART framing from the wire up: idle-high line, start bit, data bits LSB-first, optional parity,
  stop bit(s), and how baud rate maps to a bit period.
* A baud-rate generator, a transmitter, and an oversampling receiver in VHDL, each
  testbench-verified.
* Register semantics over port semantics: sticky, poll-able `STATUS` bits built from single- cycle
  pulses; a write-triggered TX push; a read-then-pop RX path, and why a read that pops a FIFO needs
  the same commit-on-completion, abort-safe discipline as a write.
* The shared [UART register protocol](./protocol/uart_register_protocol.md) both halves implement
  against, this course's single source of truth.
* A `driver::transport::Interface` seam under the C++ driver: `driver::uart::Uart` implements
  `driver::uart::Interface` over it, host-tested with a scripted `driver::transport::Stub` before
  any hardware exists.
* Freestanding C++ on the ATmega328P, and bring-up on the bench: two serial links, a level shifter,
  a bring-up ladder, and an echo application driven end to end.

---

## Prerequisites
This course is standalone and assumes only the foundational threads below, which it does **not**
re-teach:
* **Digital Design with VHDL** - `entity`/`architecture`, processes, synchronizers, state machines,
  and running a provided self-checking testbench.
* **Modern Embedded C++** - classes, interfaces, and the layered-driver idea.
* **Embedded C** - the ATmega toolchain (avr-gcc, avrdude) and register-level programming. Needed
  only from L07, when the driver reaches the real chip.

### The provided transport
The MCU-FPGA link, a byte-level `spi_slave` and a transaction-level `spi_reg_bridge`, is
handed out as testbench-verified VHDL (see [`hw/`](./hw/README.md)) and used as a black box: the
participant writes the peripheral behind it (register bank, `uart_top`) and the driver above it,
not the bridge itself. The [protocol spec](./protocol/uart_register_protocol.md) documents the
transport fully, so nothing about it is magic, only out of scope.

The box stays closed for one more course, since I2C reuses the same control plane, and is opened in the one after: building `spi_slave` and `spi_reg_bridge` from the wire up, clock-domain crossing and all, is the whole subject of SPI: The MCU-FPGA Transport, from the Wire Up. This course introduces the pattern with the transport given.

---

## Two Written Papers, and What They Are Not
Nothing in this course is marked. Assessment is the exercises after every lecture, the provided
self-checking testbench or host suite that grades each one, and the Evaluation questions that close
every lecture README. Roughly half the code the course produces lives in those exercises.

[`exam/`](./exam/README.md) holds two four-hour papers with worked solutions, and they check
something else: **what you can reconstruct on paper, with nothing in front of you.** Eight questions
each, one per lecture, in the course's own rhythm of four VHDL, three C++ and one with both halves
on the bench - mixing theory with code you either trace and repair or write from scratch, and with
no GHDL and no `make test` in the room to tell you which it is.

**They exist purely so that participants can test their own skills and knowledge after the course.
They gate nothing, they are not a qualification, and no part of the course requires them.** Nothing
in this repository depends on them: no module is built from them, and neither `make build` nor
`make format-check` knows they exist.

**Take one once the course is over**, after [L08](./lectures/L08/README.md) and the bring-up ladder.
Both papers draw on all eight lectures and on both sides of the wire, so sitting one partway through
examines material nobody has taught you yet, and the result says more about how far you have read
than about what you have understood.

---

## Structure

```text
hw/          The VHDL this course writes (baud gen, transmitter, receiver, FIFOs, register bank,
             uart_top) and the provided testbenches - plus the provided spi_slave / spi_reg_bridge
             transport. See hw/README.md for what arrives in which lecture.
fw/          The C++ this course writes: the transport seam, driver::uart::Uart, host tests, and
             the AVR port. See fw/README.md.
info/        Course info: instructor, course plan, per-lecture breakdown, and the shopping list.
lectures/    Lecture READMEs, L01-L08.
exam/        Two written papers and their solutions. Optional, and marked by nobody here.
protocol/    The UART register protocol specification - the contract both halves implement,
             including the provided SPI transport framing.
```

---

## Building
Host-side builds and tests use **g++** and **clang-format** (introduced in Modern Embedded C++
and Embedded Software Testing); VHDL is analyzed and simulated with **GHDL** (from Digital Design
with VHDL); the MCU firmware is built and flashed with **avr-gcc / avr-libc / avrdude** (the
ATmega toolchain from Embedded C), and the DE0-CV is programmed from **Quartus Prime Lite**. See
[`info/README.md`](./info/README.md) for the tool list, versions and the hardware list. Code
arrives lecture by lecture and CI stays green throughout: a directory with no Makefile yet, or a
testbench whose modules are not written yet, is skipped rather than failed.

---

