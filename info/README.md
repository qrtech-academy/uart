# Course Information

## Instructor
Erik Pihl ([erik.axel.pihl@gmail.com](mailto:erik.axel.pihl@gmail.com))

---

# Course Plan - UART: Hardware, Driver & Integration

### Part 1 - The FPGA Peripheral (VHDL)
| Lecture | Side | Topic |
|---------|------|-------|
| L01 | VHDL | The register package & the peripheral top |
| L02 | VHDL | UART framing & the transmitter |
| L03 | VHDL | The synchronizer & the receiver |
| L04 | VHDL | The FIFO & the receive path |
| L05 | VHDL | The register bank |

### Part 2 - The Driver & Integration (C++)
| Lecture | Side | Topic |
|---------|------|-------|
| L06 | C++  | The driver's contracts |
| L07 | C++  | The driver, built |
| L08 | C++  | The driver, tested |
| L09 | C++  | The real transport, and both toolchains |
| L10 | Both | Integration & bring-up |

The rhythm: five lectures of VHDL, four of C++, and one with both halves on the bench at once. Part
1 ends with a peripheral that passes its own system testbench in simulation; Part 2 crosses the wire
to the ATmega and ends with both chips talking on the bench.

---

## Format
**Ten sessions of 60 minutes each**, live-coded. The instructor types and the participants follow;
the code a session does not reach is that lecture's after-lecture exercise. Sixty minutes is roughly
ninety to a hundred lines of narrated typing once the agenda and the closing discussion are paid
for, which is less than most of these lectures produce, so every session is designed to a split:
**live-code the idea, assign the remainder**.

The table below is that budget. It is what makes the hour plannable, and it is why the heavier
lectures (L05, L09) do not overrun: the parts left out are conventional or repetitive, fully
specified in the appendices, and none of them carries an idea a participant needs to watch being
typed.

| Lecture | Live-coded in the session | Left to the exercises |
|---|---|---|
| L01 | The entity; instantiating `reset_sync` and `spi_slave`, deriving signals from their entities | The `spi_reg_bridge` instantiation, the `reg_rdata` placeholder, the check |
| L02 | `baud_gen` in full; `uart_tx`'s frame vector and state machine | `uart_tx`'s `busy` / `done` timing; instantiating both into `uart_top` |
| L03 | `sync` in full; `uart_rx`'s start detection and mid-bit sampling | The rest of `uart_rx`: the data-bit loop and the stop-bit check |
| L04 | `fifo`'s clocked process and flags; the `sync` and `uart_rx` instantiations in `uart_top` | The FIFO's corner cases; where overrun really lives |
| L05 | The computed `STATUS`; the `RX_DATA` / `RX_POP` split; the first system-testbench run | The remaining register decode; the `ERROR_FLAGS` latch |
| L06 | `register_map.hpp` and both interfaces | `driver::uart::Stub` |
| L07 | `readReg` / `writeReg`; `read()` as the poll-read-pop path | The other public methods of `driver::uart::Uart` |
| L08 | The stub's record and playback sides; the blocking helpers | The rest of `driver::transport::Stub`; the provided demo |
| L09 | `AvrSpi` in full; the Quartus flow, demonstrated | The freestanding `main`; UART logging; synthesizing your own `uart_top` |
| L10 | The bench: wiring, then the bring-up ladder | `app::EchoNode` and its test, written **before** the session |

Two consequences worth stating plainly. **L10 assumes `app::EchoNode` already works**, so its
exercise is due before the lecture rather than after it; a bench hour spent debugging application
logic is a bench hour wasted. And **the exercises are not optional padding**: they carry roughly
half the code the course produces, and the provided testbenches and host suites are what grade them.

---

## Lecture Content

### Part 1 - The FPGA Peripheral (VHDL)

#### L01 - The register package & the peripheral top (VHDL)
Top-down: the shell the whole peripheral fills in.

Topics include:
* The register map in VHDL: `uart_def` (provided), the seven register indices and the `STATUS` /
  `CTRL` / `ERROR_FLAGS` bit positions, the twin of the C++ side's `register_map.hpp`.
* `uart_top` built top-down: the entity (a positional port contract), the provided `reset_sync`
  (assert async, release sync) and the provided SPI transport, with each internal signal derived
  from the entity of the block it connects to rather than declared all at once.
* Why building the top first fixes every datapath block's interface, and how `uart_top` gains one
  block per lecture until the system testbench can run in L05.

---

#### L02 - UART framing & the transmitter (VHDL)
The wire, and the easy direction first.

Topics include:
* UART framing from the wire up: idle-high, start bit, 8 data bits LSB-first, optional parity, stop
  bit(s); how baud rate maps to a bit period.
* The baud-rate generator: a divider from the 50 MHz system clock, sized by `BAUD_DIV`.
* Live-coding the transmitter `uart_tx.vhd`: a load -> shift -> frame state machine driving `tx`,
  with `busy` / `done`, verified against a provided testbench.

---

#### L03 - The synchronizer & the receiver (VHDL)
The hard direction: recovering bytes from an asynchronous line.

Topics include:
* Synchronizing the asynchronous `rx` input with a two-flop synchronizer (`sync.vhd`) - the
  metastability lesson from Digital Design, reused on a genuinely asynchronous input.
* Why the receiver oversamples `rx` (16x) rather than clocking on it: start-bit detection, mid-bit
  sampling at tick 8 of 16, and the mid-bit re-check that rejects a glitch.
* Why idle is left on a falling edge rather than a low level, and what a break does to a receiver
  that tests the level instead.
* Framing errors surfaced as a one-cycle pulse, with parity and overrun discussed and scoped out;
  live-coding `uart_rx.vhd` and feeding it good and deliberately corrupted frames from its
  testbench.

---

#### L04 - The FIFO & the receive path (VHDL)
The buffer the register bank needs two of, and the wiring that puts L03's work into the top.

Topics include:
* A small synchronous FIFO (`fifo.vhd`): a ring buffer with head, tail and count, written once as a
  generic module because L05 instantiates it twice.
* The look-then-advance read - `rdata` shows the front entry, `rd` discards it - and why that split
  is exactly what lets L05 keep `RX_DATA` a pure read with a separate `RX_POP`.
* The corner cases a count gets wrong: a write to a full FIFO, a read from an empty one, and a `wr`
  and `rd` on the same edge.
* Instantiating the receive path into `uart_top`: `sync` on the `rx` pin, then `uart_rx` behind it,
  so the pin crosses into the clock domain once, in the module that owns it.
* Why overrun is not a question the receiver can answer, and which block gets asked it instead.

---

#### L05 - The register bank (VHDL)
Ports become registers; the FPGA half is complete.

Topics include:
* Wrapping TX/RX behind the register map: `STATUS`, `CTRL`, `BAUD_DIV`, `TX_DATA`, `RX_DATA`,
  `RX_POP`, `ERROR_FLAGS`.
* Two TX/RX FIFOs from L04; pulse-to-sticky `ERROR_FLAGS` latching; a write-triggered TX push; and
  the read-then-pop RX path - why a read that pops a FIFO needs commit-on-completion and the `SS`
  abort rule, unlike a pure status read.
* Instantiating the register bank, and the two FIFOs it owns, into the `uart_top` skeleton from L01,
  the last block it was waiting for, behind the provided `spi_slave` / `spi_reg_bridge` transport (a
  testbench-verified black box).
* The system testbench, running for the first time: write `TX_DATA` and watch the byte leave on
  `tx`, with `rx` looped back to `tx` inside the bench.

---

### Part 2 - The Driver & Integration (C++)

#### L06 - The driver's contracts (C++)
Crossing to C++: the three abstractions the driver rests on, before any algorithm.

Topics include:
* The register map in C++: the seven indices and the `STATUS` / `CTRL` / `ERROR_FLAGS` bits as
  `constexpr` constants shared with `uart_def.vhd`.
* The transport interface (`driver::transport::Interface`), whose three calls are `begin` /
  `transfer` / `end`, and why a byte-level seam is what makes the driver host-testable.
* The `driver::uart::Interface`: configure, write, read, poll status and clear errors. It is
  abstract and non-blocking, the API every transport implementation sits behind.
* A first implementation of it, `driver::uart::Stub`, left to the exercises so the week ends with a
  concrete class and not only declarations; L10 uses it as the whole test harness for
  `app::EchoNode`.

---

#### L07 - The driver, built (C++)
The contracts get an implementation. Nothing runs it yet, which is what makes the reasoning matter.

Topics include:
* `readReg()` / `writeReg()` as 5-byte SPI transactions over the transport interface, most
  significant byte first, and why a reversed value is a different value to the hardware.
* `const` at a hardware boundary: why `readReg()` is a `const` member driving a non-`const`
  transport, what the `const_cast` documents, and what it is not doing.
* `driver::uart::Uart` implementing the L06 interface: `configure`, the non-blocking `write`, and
  the poll / read / separate `RX_POP` read path.
* Why the read path is three register accesses and not one, and what each of them breaks if it is
  dropped, reordered, or folded into the one before it.

---

#### L08 - The driver, tested (C++)
The wire, scripted, and the first `make test` the C++ half of the course has had.

Topics include:
* A scripted `driver::transport::Stub`: it records every byte the driver sends and plays back bytes
  a test queued for it - the C++ counterpart of a self-checking testbench.
* Host tests with QAcademy Test that assert the exact transactions, the byte order, the balanced
  `begin` / `end` framing, and the "no `RX_POP` on empty" behaviour.
* Testing the test double first: why the four `TransportStub` cases run before any driver case, and
  why a stub bug reports itself as a driver failure.
* Blocking `write` and `read` as thin free functions over the non-blocking core, taking `Interface&`
  rather than `Uart&`, plus a provided demo that exercises the API end to end.

---

#### L09 - The real transport, and both toolchains (C++)
The bottom layer becomes real; nothing above the seam changes, and both chips get programmed.

Topics include:
* The AVR `SPCR`/`SPSR`/`SPDR` as genuine memory-mapped `volatile` registers, configured as an SPI
  master at 1 MHz, mode 0, MSB first.
* `AvrSpi` implementing the `driver::transport::Interface` seam, so the L07 driver and the L08 host
  tests are reused unchanged.
* What a freestanding target removes (heap, exceptions, RTTI, iostreams) and what replaces each;
  building with avr-gcc and flashing with avrdude.
* The other toolchain: synthesizing `uart_board.vhd` in Quartus Prime Lite, reading the fit and
  timing report, and programming the DE0-CV over USB-Blaster, so the FPGA is running your code
  before bring-up day rather than on it.

---

#### L10 - Integration & bring-up (Both)
Both halves on the bench; the pyramid gets its top.

Topics include:
* Two links wired up: SPI (Nano <-> DE0-CV, through the level shifter) for control, and the
  peripheral's `tx`/`rx` to a 3.3 V USB-serial adapter for data. The FPGA is already synthesized and
  programmed, from L09.
* The bring-up ladder: a data-plane pin loopback in the board wrapper, then the control plane proven
  by a `BAUD_DIV` write and read-back over SPI, then peripheral loopback (`tx`->`rx`) under driver
  control, then the real data plane against a PC terminal, then a full `app::EchoNode`.
* What each rung establishes that the previous one cannot, and what the integration level catches
  that no host test can.
* Closing discussion: one byte traced end to end - PC terminal, FPGA UART, register bank, SPI
  bridge, ATmega driver, and back - naming every module.

---

## Course Material

### Literature
* Lecture notes.
* The [UART register protocol specification](../protocol/uart_register_protocol.md).
* Code examples and provided testbenches.
* Exercises completed after the lectures, with reference solutions.

---

### Software
Versions are given as the floor the build actually requires, then the version the repository is
developed and CI-tested against.

* **Visual Studio Code** - primary editor.
* **GCC / G++** - host-side builds and tests (from Modern Embedded C++ / Embedded Software Testing).
  The host build is `-std=c++17`, so **g++ 7 or newer**; developed against 13.3.
* **GHDL** - VHDL analysis and simulation (from Digital Design with VHDL). Everything is analyzed
  `--std=93`, so **any GHDL 3.0 or newer** works; developed against 4.1.0, mcode backend.
* **avr-gcc, avr-libc, avrdude** - building and flashing the ATmega328P firmware (`sudo apt -y
  install gcc-avr avr-libc avrdude`). The AVR build is deliberately `-std=c++14`, not C++17, so that
  it also builds on the older compiler Microchip Studio ships: **avr-gcc 5 or newer**; developed
  against 7.3.0.
* **clang-format** - the C/C++ style check run by `make format-check`; developed against 18.1.3.
* **Quartus Prime Lite** - synthesizing and programming the DE0-CV. Needs a version with Cyclone V
  support, so **20.1 or newer**.
* **A serial terminal** - `picocom`, `minicom` or `screen` on Linux/WSL, PuTTY on Windows. Used at
  115200 8N1 as the far end of the data plane in L09 and L10.
* **Linux / WSL** - terminal environment for all of the above.

---

### Hardware
Per bench:
* **Terasic DE0-CV** - the FPGA board; provided.
* **Arduino Nano (ATmega328P)** - any 5 V / 16 MHz Nano or clone.
* **4-channel bidirectional level shifter** (e.g. BSS138-based) - the four SPI lines cross 5 V <->
  3.3 V.
* **3.3 V USB-serial adapter** (e.g. CP2102 or FT232 set to 3.3 V logic) - the data-plane peer for
  the peripheral's `tx`/`rx`. A second Arduino can stand in.
* **Breadboard and jumper wires**; one USB cable per Nano, and one USB Type-B cable plus the 12 V
  supply for the DE0-CV's on-board USB-Blaster.
* Optional but recommended: a **logic analyzer** (any 8-channel 24 MHz unit is plenty at 1 MHz SCK
  and 115200 baud). One L09 exercise uses it and says so; nothing else depends on it.

---

