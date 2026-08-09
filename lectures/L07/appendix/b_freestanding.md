# Appendix B

## The freestanding target and the toolchain
The host build (g++) links against a full hosted C++ implementation: a heap, exceptions, RTTI,
iostreams, the whole standard library. The ATmega328P has none of that. Its build is
**freestanding**: avr-gcc, no operating system, and only the thin runtime avr-libc provides.
This appendix is about what that removes, why the driver survives it unchanged, and how you build
and flash.

---

### What freestanding removes, and what replaces it
A freestanding avr-gcc build is compiled with `-std=c++14 -mmcu=atmega328p -Os -DF_CPU=16000000UL
-fno-exceptions -fno-rtti -fno-threadsafe-statics`, plus `-ffunction-sections -fdata-sections` and a
linker `-Wl,--gc-sections` so the linker can drop what virtual dispatch pulls in on a 32 KB part.
Everything the driver uses is C++11, so the standard here is a floor rather than a requirement;
`-std=c++14` is chosen because every avr-gcc in circulation accepts it, while `-std=c++17` is not
even a recognized option on the older toolchains, including the one Microchip Studio ships. Three
things go away with the rest of the flags. **The heap** goes first: avr-libc does provide `malloc`
and `free`, but there is no C++ `operator new` or `operator delete`, so dynamic allocation is off
the table in practice and you use static and automatic storage. **Exceptions and RTTI** go next,
which means no `throw`, no `dynamic_cast` and no `typeid`, and errors become return values, which is
exactly what the driver already does when `write` returns `false` on a full FIFO. Finally
**iostreams and most of the standard library** go, so there is no `std::cout` and logging goes out a
real UART instead, as described below.

The payoff of the AVR-portable style from L05 lands here. Because the register map, `Interface`,
`Uart`, `Stub` and the blocking helpers were all written with `<stdint.h>` and bare types, no
`std::`, nested namespace blocks, and none of the newer C++ attributes the AVR toolchain rejects,
they cross-compile to the target **untouched**. Nothing above the seam is rewritten for the AVR;
only the transport below it is new. That is the whole point of having built portable in the first
place.

---

### `env.cpp`, the runtime the compiler still expects
avr-libc ships no C++ runtime, yet the compiler still emits references to a few runtime symbols for
ordinary C++ constructs, and the link fails without them. The provided `avr/env.cpp` hand-defines
three groups of them. `operator delete` is needed because a class with a virtual destructor names the
deleting `operator delete` in its vtable, even if you never delete through a base pointer.
`__cxa_pure_virtual()` is named by every abstract class' vtable, and is called only if a pure virtual
is somehow invoked. And `__cxa_guard_acquire()`, `__cxa_guard_release()` and `__cxa_guard_abort()`
form the guard around a function-local `static`'s one-time initialization.

This build passes `-fno-threadsafe-statics`, so avr-gcc never emits the `__cxa_guard_*` calls at
all; `env.cpp` defines them anyway, so the link succeeds with or without the flag and on any
toolchain that does emit them. `env.cpp` lives in `avr/`, not `source/`, on purpose: the host build
already has these from libstdc++, so keeping the file out of the host link avoids replacing the
host's thread-safe static guards with the single-threaded versions. The details are in
[`fw/README.md`](../../../fw/README.md).

---

### Logging over the AVR's own UART
With no iostreams, debug logging goes out the ATmega328P's **own hardware USART** (its `TXD`/`RXD`
pins, the "serial" a Nano exposes over USB). Do not confuse it with the UART peripheral this whole
course builds: that one lives on the FPGA and the ATmega drives it over SPI; this one is the
ATmega's built-in serial port, used here purely as a debug console to a PC terminal.

Using it is a small, poll-based routine: set the baud divider `UBRR0` from `F_CPU` and the target
baud, enable the transmitter in `UCSR0B`, then for each byte wait for the data register to be empty
(`UCSR0A & (1U << UDRE0)`) and write it to `UDR0`. This is why the logging path, unlike the SPI
transport, needs `F_CPU`: the baud divider is computed from the clock.

---

### Building and flashing the MCU
Two steps turn the source into something on the chip. First you **compile and link** with avr-gcc for
`-mmcu=atmega328p`, then `avr-objcopy` the ELF into an Intel HEX image. Then you **flash** it with
avrdude over the Nano's USB bootloader. Both are wrapped by the avr-gcc Makefile in `avr/`:

```bash
make -C fw/avr flash
```

---

### The other toolchain: getting the peripheral onto the FPGA
The FPGA half has the same journey, and this is where it happens, because the two are the same idea
twice: source becomes an image, an image gets programmed onto a part.

Everything up to now has been GHDL, which only ever simulated your VHDL. Simulation says the design
is *correct*; it says nothing about whether it **fits** on the device or **meets timing** at 50 MHz.
Only synthesis answers those, and the tool for the DE0-CV is **Quartus Prime Lite**.

`uart_top` is not the top level on the board. It has no notion of which physical pin `sclk` or `tx`
is, so it is wrapped by **`uart_board.vhd`**, the provided Quartus top level that maps its ports onto
DE0-CV package pins and feeds it the board's 50 MHz clock. That wrapper is board I/O rather than
peripheral logic, which is why it lives with the Quartus project instead of in `hw/`.

The flow is: open the project, add your `hw/*.vhd` alongside the wrapper, **compile**, then read the
two numbers that matter. **Fit** tells you the design is small enough, which for this peripheral it
comfortably is. **Timing** tells you every path from flip flop to flip flop settles inside one 20 ns
clock period; a design that simulates perfectly can still fail here, and that failure is invisible to
every testbench you have run. Then **program** the board over USB-Blaster.

To see it work with nothing else attached, jumper the peripheral's `tx` pin to its `rx` pin and let
it echo itself. That is the same loopback `uart_top_tb` performs in simulation, running now on real
silicon at a real 50 MHz, and it is the last thing the FPGA half needs before both chips meet on the
bench in L08.

`F_CPU` must match the board's actual clock (16 MHz on a standard Nano, set by its crystal, with the
fuses selecting that external oscillator as the clock source), because
it drives every computed timing, including the debug UART's baud. The `avr/` build is
cross-compiled and flashed only; it is excluded from host CI, while the transport's *logic* is
still checked on the host per [Appendix A](./a_avr_transport.md).

---

## What's ahead
[Appendix C](./c_exercises.md) is the exercises: implement `AvrSpi`, write the freestanding
bring-up `main`, add UART logging, and measure a register round trip against the 1 MHz SCK budget.
L08 then puts both halves on the bench.

---

