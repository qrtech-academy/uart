# Appendix A

## The SPI peripheral and `AvrSpi`
This is the bottom of the stack, and the one place the code finally touches real hardware.
Everything above the seam, the register map, the `Interface`, the `Uart` driver, was built and
host-tested in L05 and L06 against a scripted `Stub`. Here you implement the *other*
`driver::transport::Interface`, the one that drives the ATmega328P's own SPI peripheral, so the
exact same driver runs over a real 1 MHz SPI bus with nothing above the seam changing.

`AvrSpi` is deliberately thin: it configures the SPI master once, then translates the three seam
calls into register accesses. All the protocol knowledge (5-byte transactions, the command byte,
byte order) already lives in the driver above it.

---

### The SPI registers
The ATmega328P's SPI is three `volatile` memory-mapped registers. This is the `volatile` lesson from
Modern Embedded C++, now on the master side of the wire: the compiler must not cache or reorder these
accesses, because each one is a real bus event.

| Register | Bit | Meaning |
|---|---|---|
| `SPCR` | `SPE`   | SPI enable. |
| `SPCR` | `MSTR`  | Master (1) or slave (0). |
| `SPCR` | `DORD`  | Data order: 0 = MSB first, 1 = LSB first. |
| `SPCR` | `CPOL`  | Clock polarity: 0 = SCK idles low. |
| `SPCR` | `CPHA`  | Clock phase: 0 = sample on the leading edge. |
| `SPCR` | `SPR1` / `SPR0` | SCK rate select (with `SPI2X`). |
| `SPSR` | `SPIF`  | Transfer complete (set when a byte has finished shifting). |
| `SPSR` | `SPI2X` | Double the SCK rate. |
| `SPDR` | -       | Data register: write to start a transfer, read to get the byte clocked in. |

The transport contract from [Part 3 of the protocol
spec](../../../protocol/uart_register_protocol.md) pins every one of these. The ATmega is the
**master**, running **mode 0** (`CPOL` = 0, `CPHA` = 0), **MSB first** (`DORD` = 0), with `SCK` at
**f_osc/16 = 1 MHz**, the Nano's 16 MHz clock divided by 16 (`SPR1:SPR0` = `01`, `SPI2X` = 0).

1 MHz is not a limit the FPGA imposes: `spi_slave` synchronizes `sclk` into the 50 MHz domain and
edge-detects it, so it keeps up with far more than this. It is simply the nearest prescaler value
below the rate at which a breadboard and a passive level shifter stop being reliable, and it leaves
comfortable margin for both.

---

### Configuring the master
Configuration is a one-time setup of `SPCR`, plus the port pins. On the ATmega328P the SPI pins are
fixed: `SCK` = PB5, `MOSI` = PB3, `MISO` = PB4, and the hardware `SS` = PB2. Two details matter. The
first is direction: `SCK`, `MOSI` and `SS` are outputs while `MISO` is an input, and you set that in
`DDRB`. The second is that `SS` (PB2) **must be an output** in master mode. If it is left an input
and something pulls it low, the peripheral clears `MSTR` and demotes itself to a slave mid-flight.
PB2 doubles as the chip select to the FPGA, so driving it is the transport's job anyway.

---

### Releasing the registers on destruction
The constructor is the one place that *sets* bits, so the destructor is the one place that clears
them: `AvrSpi` acquires the SPI hardware when it is constructed and **must release it when it is
destroyed**, leaving the registers exactly as the reset left them. Clear every bit the constructor
set, and nothing else: the `DDRB` direction bits for `SCK`, `MOSI` and `SS`, putting them back to
inputs; the `SS` bit in `PORTB`, which is the chip-select drive and its pull-up; and all of `SPCR`,
written to `0`, which disables the SPI peripheral.

`MISO` was never configured, so leave it untouched. The destructor is `noexcept` and, because the
transport `Interface` declares a virtual destructor, is marked `override`, so destroying an `AvrSpi`
through an `Interface&` still runs it. This is plain RAII: whatever the constructor took, the
destructor gives back, so the next owner of those pins - a second `AvrSpi`, or any other code -
starts from the power-on state rather than a half-configured SPI master.

---

### The three seam methods
The seam maps directly onto the peripheral. `begin()` drives the chip select low (`SS`/PB2), opening
a transaction, and `end()` releases it high again, closing it. Between them, `transfer(byte)`
exchanges one byte in full duplex: write the byte to `SPDR`, wait for the hardware to finish, then
read `SPDR` for the byte that arrived on `MISO`.

That wait is the whole subtlety. A byte takes eight SCK periods to shift, and `SPDR` does not hold
the received byte until the transfer completes, signalled by `SPIF` going high:

```cpp
SPDR = byte;
while (0U == (SPSR & (1U << SPIF))) {} // Spin until the transfer completes.
return SPDR;                           // Now SPDR holds the received byte.
```

Read `SPDR` *before* `SPIF` is set and you get stale data from the previous exchange, so the poll is
not optional. (Reading `SPSR` then `SPDR` also clears `SPIF`, arming the next transfer.) This is the
same three-method seam the L06 `Stub` implemented; the difference is that these bytes are real.

---

### Testing it on the host
The transport touches hardware, but its *logic* is still worth pinning without a bench, so it is
host-tested exactly like the L06 `Stub` was, over a mocked register file. On the target, `AvrSpi`
reaches the registers through a platform header (`arch/avr/hw_platform.hpp`), which forwards to
`<avr/io.h>` and resolves `SPCR`, `SPSR`, `SPDR`, `DDRB` and `PORTB` to the real memory-mapped
hardware. On the host, that same platform header selects a provided mock instead, under
`-DHOST_TEST`, which backs `DDRB`, `PORTB` and `SPCR` with plain storage and makes `SPDR` and `SPSR`
proxy objects, so that reading them has an effect the way it does on the part. It records the bytes
written to `SPDR` as a `MOSI` log and returns a scripted byte on each `SPDR` read from a `MISO`
queue, and it models the one property that matters here: a transfer takes time. Writing `SPDR`
starts it, `SPIF` stays **clear**, and only a read of `SPSR` - the driver's own poll - completes the
transfer and makes the received byte readable. Delete the poll and `transfer()` hands back the
*previous* byte, and the suite goes red. It is the direct counterpart of the `Stub`.

With that mock, a provided host suite pins the register-level behaviour the bench cannot easily show:
the master configuration bits, the chip-select framing (`begin` low, `end` high), the `SPIF` poll,
and that `transfer` returns the byte the mock presented, in order. Only the register file needs
mocking; the transport uses no interrupts and no `F_CPU`-derived timing, so neither
`<avr/interrupt.h>` nor `F_CPU` come into it. The whole transport is then proven end to end on the
bench in L08.

---

## What's ahead
[Appendix B](./b_freestanding.md) covers the target the transport is built for: a freestanding
avr-gcc build, what it removes, the `env.cpp` runtime stubs, and flashing with avrdude. The
[exercises](./c_exercises.md) implement `AvrSpi`, the freestanding bring-up `main`, and
UART-based logging.

---

