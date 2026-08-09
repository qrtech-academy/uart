# Course Information

## Instructor
Erik Pihl ([erik.axel.pihl@gmail.com](mailto:erik.axel.pihl@gmail.com))

---

# Course Plan - UART: Hardware, Driver & Integration

| Lecture | Side | Topic |
|---------|------|-------|
| L01 | VHDL | The register package & the peripheral top |
| L02 | VHDL | UART framing & the transmitter |
| L03 | VHDL | The receiver & the FIFO |
| L04 | VHDL | The register bank |
| L05 | C++  | The driver's contracts |
| L06 | C++  | The driver, built and tested |
| L07 | C++  | The real transport, and both toolchains |
| L08 | Both | Integration & bring-up |

The rhythm: four lectures of VHDL, three of C++, and one with both halves on the bench at once.

---

## Format
**Eight sessions of 60 minutes each**, live-coded. The instructor types and the participants follow;
the code a session does not reach is that lecture's after-lecture exercise. Sixty minutes is roughly
ninety to a hundred lines of narrated typing once the agenda and the closing discussion are paid
for, which is less than most of these lectures produce, so every session is designed to a split:
**live-code the idea, assign the remainder**.

The table below is that budget. It is what makes the hour plannable, and it is why the heavier
lectures (L03, L04, L06) do not overrun: the parts left out are conventional or repetitive, fully
specified in the appendices, and none of them carries an idea a participant needs to watch being
typed.

| Lecture | Live-coded in the session | Left to the exercises |
|---|---|---|
| L01 | The entity; instantiating `reset_sync` and `spi_slave`, deriving signals from their entities | The `spi_reg_bridge` instantiation, the `reg_rdata` placeholder, the check |
| L02 | `baud_gen` in full; `uart_tx`'s frame vector and state machine | `uart_tx`'s `busy` / `done` timing; instantiating both into `uart_top` |
| L03 | `sync`; `uart_rx`'s start detection and mid-bit sampling | The rest of `uart_rx`; all of `fifo` |
| L04 | The computed `STATUS`; the `RX_DATA` / `RX_POP` split; the first system-testbench run | The remaining register decode; the `ERROR_FLAGS` latch |
| L05 | `register_map.hpp` and both interfaces | `driver::uart::Stub` |
| L06 | `readReg` / `writeReg`; `read()` as the poll-read-pop path | The other public methods; `driver::transport::Stub`; the blocking helpers |
| L07 | `AvrSpi` in full; the Quartus flow, demonstrated | The freestanding `main`; UART logging; synthesizing your own `uart_top` |
| L08 | The bench: wiring, then the bring-up ladder | `app::EchoNode` and its test, written **before** the session |

Two consequences worth stating plainly. **L08 assumes `app::EchoNode` already works**, so its
exercise is due before the lecture rather than after it; a bench hour spent debugging application
logic is a bench hour wasted. And **the exercises are not optional padding**: they carry roughly
half the code the course produces, and the provided testbenches and host suites are what grade them.

---

## Lecture Content

### L01 - The register package & the peripheral top (VHDL)
Top-down: the shell the whole peripheral fills in.

Topics include:
* The register map in VHDL: `uart_def` (provided), the seven register indices and the `STATUS` /
  `CTRL` / `ERROR_FLAGS` bit positions, the twin of the C++ side's `register_map.hpp`.
* `uart_top` built top-down: the entity (a positional port contract), the provided `reset_sync`
  (assert async, release sync) and the provided SPI transport, with each internal signal derived
  from the entity of the block it connects to rather than declared all at once.
* Why building the top first fixes every datapath block's interface, and how `uart_top` gains one
  block per lecture until the system testbench can run in L04.

---

### L02 - UART framing & the transmitter (VHDL)
The wire, and the easy direction first.

Topics include:
* UART framing from the wire up: idle-high, start bit, 8 data bits LSB-first, optional parity, stop
  bit(s); how baud rate maps to a bit period.
* The baud-rate generator: a divider from the 50 MHz system clock, sized by `BAUD_DIV`.
* Live-coding the transmitter `uart_tx.vhd`: a load -> shift -> frame state machine driving `tx`,
  with `busy` / `done`, verified against a provided testbench.

---

### L03 - The receiver & the FIFO (VHDL)
The hard direction: recovering bytes from an asynchronous line, plus the buffer L04 will need.

Topics include:
* Why the receiver oversamples `rx` (16x) rather than clocking on it: start-bit detection, mid-bit
  sampling, and optional majority voting.
* Synchronizing the asynchronous `rx` input with a two-flop synchronizer - the metastability lesson
  from Digital Design, reused.
* Framing errors surfaced as a flag, with parity and overrun discussed and scoped out; live-coding
  `uart_rx.vhd` and feeding it good and deliberately corrupted frames from its testbench.
* A small synchronous FIFO (`fifo.vhd`) with a look-then-advance read, built here so that L04 is one
  module rather than two.

---

### L04 - The register bank (VHDL)
Ports become registers; the FPGA half is complete.

Topics include:
* Wrapping TX/RX behind the register map: `STATUS`, `CTRL`, `BAUD_DIV`, `TX_DATA`, `RX_DATA`,
  `RX_POP`, `ERROR_FLAGS`.
* Two TX/RX FIFOs from L03; pulse-to-sticky `ERROR_FLAGS` latching; a write-triggered TX push; and
  the read-then-pop RX path - why a read that pops a FIFO needs commit-on-completion and the `SS`
  abort rule, unlike a pure status read.
* Instantiating the register bank, and the two FIFOs it owns, into the `uart_top` skeleton from L01,
  the last block it was waiting for, behind the provided `spi_slave` / `spi_reg_bridge` transport (a
  testbench-verified black box).
* The system testbench, running for the first time: write `TX_DATA` and watch the byte leave on
  `tx`, with `rx` looped back to `tx` inside the bench.

---

### L05 - The driver's contracts (C++)
Crossing to C++: the three abstractions the driver rests on, before any algorithm.

Topics include:
* The register map in C++: the seven indices and the `STATUS` / `CTRL` / `ERROR_FLAGS` bits as
  `constexpr` constants shared with `uart_def.vhd`.
* The transport interface (`driver::transport::Interface`), whose three calls are `begin` /
  `transfer` / `end`, and why a byte-level seam is what makes the driver host-testable.
* The `driver::uart::Interface`: configure, write, read, poll status and clear errors. It is
  abstract and non-blocking, the API every transport implementation sits behind.
* A first implementation of it, `driver::uart::Stub`, left to the exercises so the week ends with a
  concrete class and not only declarations; L08 uses it as the whole test harness for
  `app::EchoNode`.

---

### L06 - The driver, built and tested (C++)
The contracts get an implementation, verified on the host with no hardware.

Topics include:
* `readReg()` / `writeReg()` as 5-byte SPI transactions over the transport interface, most
  significant byte first.
* `driver::uart::Uart` implementing the interface: configure, the non-blocking `write`, and the poll
  / read / separate `RX_POP` read path.
* A scripted `driver::transport::Stub` and host tests with QAcademy Test that assert the exact
  transactions, the byte order, and the "no `RX_POP` on empty" behaviour; blocking helpers over the
  non-blocking core.

---

### L07 - The real transport, and both toolchains (C++)
The bottom layer becomes real; nothing above the seam changes, and both chips get programmed.

Topics include:
* The AVR `SPCR`/`SPSR`/`SPDR` as genuine memory-mapped `volatile` registers, configured as an SPI
  master at 1 MHz, mode 0, MSB first.
* `AvrSpi` implementing the `driver::transport::Interface` seam, so the L06 driver and its host
  tests are reused unchanged.
* What a freestanding target removes (heap, exceptions, RTTI, iostreams) and what replaces each;
  building with avr-gcc and flashing with avrdude.
* The other toolchain: synthesizing `uart_board.vhd` in Quartus Prime Lite, reading the fit and
  timing report, and programming the DE0-CV over USB-Blaster, so the FPGA is running your code
  before bring-up day rather than on it.

---

### L08 - Integration & bring-up (Both)
Both halves on the bench; the pyramid gets its top.

Topics include:
* Two links wired up: SPI (Nano <-> DE0-CV, through the level shifter) for control, and the
  peripheral's `tx`/`rx` to a 3.3 V USB-serial adapter for data. The FPGA is already synthesized and
  programmed, from L07.
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
  115200 8N1 as the far end of the data plane in L07 and L08.
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
  and 115200 baud). One L07 exercise uses it and says so; nothing else depends on it.

---

