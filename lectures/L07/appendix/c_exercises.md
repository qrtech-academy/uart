# Appendix C

## Exercises
Exercise 1 reinforces [Appendix A](./a_avr_transport.md); Exercises 2, 3 and 4 reinforce
[Appendix B](./b_freestanding.md). `AvrSpi` joins the other transport code in `driver/transport/`;
the bring-up `main` and the logging go in the AVR-only tree `fw/avr/`, next to the provided
`env.cpp` and avr-gcc Makefile. The runtime stubs, the Makefile, and the host register mock are all
provided.

`AvrSpi` reaches the SPI registers through the platform header (`arch/avr/hw_platform.hpp`, which
forwards to `<avr/io.h>` on the target and to the mock under `-DHOST_TEST`), so the same source
compiles for the target (real registers) and for the host suite (the mocked register file). Because
it touches AVR registers, the host `make build` skips `avr_spi.cpp`; the AVR build compiles it for
the target, and the host test suite compiles it against the mock.

Keep the AVR-portable style from L05: `<stdint.h>` and bare types, nested namespace blocks, no
`[[nodiscard]]`.

---

## Exercise 1 - `AvrSpi`
**a)** In `include/driver/transport/avr_spi.hpp` (declaration) and
`source/driver/transport/avr_spi.cpp` (definitions), create a new class `AvrSpi`, a second
implementation of `driver::transport::Interface` (the first was the L06 `Stub`), beside
`interface.hpp` and `stub.hpp`. Reach the registers through `arch/avr/hw_platform.hpp`.

Configure the SPI master once, from Appendix A's bit table: set the `DDRB` directions, with `SCK`,
`MOSI` and `SS` as outputs and `MISO` as an input; idle the chip select (`SS`) high by writing to
`PORTB`; and set `SPCR` for enable, master, mode 0, MSB first and f_osc/16.

Then give the destructor the mirror job: clear exactly the bits the constructor set -
`SCK`/`MOSI`/`SS` in `DDRB`, `SS` in `PORTB`, and all of `SPCR` - so an `AvrSpi` leaves the
registers as it found them, the ATmega's reset state (Appendix A, *Releasing the registers on
destruction*). Leave `MISO` alone; the constructor never touched it.

Do not restate the protocol; the driver above already owns it.

**b)** Implement the three seam methods: `begin()` drives `SS` low, `end()` drives it high, and
`transfer(byte)` writes `SPDR`, spins until `SPIF` is set, then returns `SPDR`. Explain, in one
sentence, why the spin cannot be skipped.

**c)** `SS` (PB2) is configured as an output even though the transport drives the chip select itself.
What does the SPI peripheral do if `SS` is left an input and something pulls it low mid-transaction,
and which `SPCR` bit changes?

**d)** A colleague writes `return SPDR;` immediately after `SPDR = byte;`, with no poll. What byte
comes back, and why? Tie your answer to the transfer waveform: how many `SCK` periods must pass
first?

**e)** The check: run the provided host suite (`make test`), which drives `AvrSpi` over the
mocked register file and asserts the configuration bits, the chip-select framing, the `SPIF` poll,
and the returned byte. Confirm the L06 driver suite still passes unchanged, since nothing above the
seam moved. The transport itself is finally proven on the bench in L08.

---

## Exercise 2 - The freestanding bring-up `main`
**a)** In `fw/avr/`, write a small `main()` that constructs a `Uart` over an `AvrSpi`,
`configure()`s it for 115200 8N1 (`BAUD_DIV` = 27), sends a byte with `writeBlocking`, and reads one
back. Cross-compile and flash it:

```bash
make -C fw/avr flash
```

**b)** Name one idiom from the host demo (`source/main.cpp`) that would **not** compile in this
freestanding build, and say what replaces it on the AVR. (Consider the heap, exceptions, and
iostreams.)

**c)** Delete `env.cpp` from the link and rebuild. Which symbol does the linker report as undefined,
which C++ construct in your code emitted the reference to it, and why does the host build not need
the file?

---

## Exercise 3 - Logging and timing
**a)** Add debug logging over the ATmega328P's **own** hardware USART (not the FPGA peripheral): set
`UBRR0` from `F_CPU` and the log baud, enable the transmitter in `UCSR0B`, then send each byte by
waiting on `UCSR0A & (1 << UDRE0)` and writing `UDR0`. Log one line per register transaction so you
can watch the driver work from a PC terminal.

**b)** *(Needs a logic analyzer; do the arithmetic either way and skip the capture if you have
none.)* Put a logic analyzer on the four SPI lines and capture one `readReg()`. A register read is a
5-byte transaction at 1 MHz `SCK`; work out how many `SCK` cycles that is and how long it should
take, then compare against what you measure. Where does the extra time between bytes come from?

**c)** The SPI transport needs no `F_CPU`, but this logging does. Explain the difference: what sets
the SPI `SCK` rate, and what sets the USART baud rate?

---

## Exercise 4 - Your own `uart_top` on the board
The Quartus flow is demonstrated in the session; this is where you run it yourself, so that the FPGA
is already carrying your code when the bench session starts rather than on the day.

**a)** Open the provided Quartus project, add your own `hw/*.vhd` alongside the provided
`uart_board.vhd` wrapper, and compile. Record two numbers from the reports: how much of the Cyclone V
the design uses, and the **worst-case slack** on the 50 MHz clock. Did it meet timing, and how do you
know from the report rather than from the design working?

**b)** Program the DE0-CV over USB-Blaster, then jumper the peripheral's `tx` pin to its `rx` pin and
open a terminal at 115200 8N1 on the USB-serial adapter. Typing a character should echo it back. That
is the loopback `uart_top_tb` ran in simulation, now on real silicon.

**c)** The loopback in (b) proves rather less than the simulation did, and rather more. Name one
thing each establishes that the other cannot.

---

