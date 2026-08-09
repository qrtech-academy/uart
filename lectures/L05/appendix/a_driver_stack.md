# Appendix A

## The L05 driver stack (the contracts)
L05 crosses from VHDL to C++, and it starts with the *shapes*: the three abstractions the driver
will rest on. None of them contains an algorithm yet; they are the register map, the transport
interface, and the driver interface. Designing them well is what makes the driver (L06) short and
host-testable.

Two of the three are abstract interfaces, so each lives in its own namespace: the driver's public
API is `driver::uart::Interface`, and the transport seam it runs over is
`driver::transport::Interface`. Naming both `Interface`, in separate namespaces, is deliberate: each
subsystem exposes one seam by that name.

Everything here is written by you. The three contracts are declarations; the exercises then implement
the driver interface once, as `driver::uart::Stub`, so L05 ends with a concrete class rather than
three headers. The provided host tests arrive in L06, once the `Uart` that implements the same
interface exists.

The full stack, top to bottom:

| Layer | Built in | Role |
|---|---|---|
| the application (`app::EchoNode`) | C++ (L08) | Uses the driver through its abstract interface. |
| `driver::uart::Interface` | C++ (L05) | The abstract driver API the application depends on. |
| `driver::uart::Stub` | C++ (L05) | A test double implementing that interface; L08's whole harness for `app::EchoNode`. |
| `driver::uart::Uart` | C++ (L06) | Implements the driver interface using the register protocol. |
| `driver::transport::Interface` | C++ (L05) | The abstract SPI byte seam the driver runs over. |
| a scripted stub / the real SPI | C++ (L06 / L07) | `driver::transport::Stub` for host tests; the AVR SPI on hardware. |

The register map both halves share lives in `driver/uart/register_map.hpp`.

---

## The register map
The C++ side needs the same register map the hardware has: the seven register indices and the
meaning of each `STATUS`, `CTRL`, and `ERROR_FLAGS` bit, from [Part 2 of the protocol
spec](../../../protocol/uart_register_protocol.md). It comes from the same source as `uart_def.vhd`
on the other side of the wire, and where a name exists on both sides the value must be identical;
you declare only the bits this driver actually uses. You transcribe it once, as named constants, so
nothing above ever writes a bare `3` where it means "the `TX_DATA` register". A value here that
disagrees with the hardware is a bug you would only find on the bench, so it is worth copying
carefully.

---

## The transport seam
The driver will never talk to SPI directly. It talks to an abstract seam,
`driver::transport::Interface`, that does one thing: exchange raw bytes over one SPI transaction. A
transaction is *select* (pull `SS` low), some byte exchanges, then *deselect* (release `SS`),
matching the framing in [Part 3 of the spec](../../../protocol/uart_register_protocol.md). Each byte
exchange is duplex: the same call sends one byte and returns the byte that arrived on `MISO` at the
same time, because that is exactly how SPI works, a bit out and a bit in on every clock.

Putting the seam at the *byte* level, rather than exposing register reads and writes directly, is
the deliberate choice. It keeps the SPI-specific knowledge (5-byte transactions, the command byte,
byte order) in one place, the driver, and lets the layer below be a dumb byte pipe that a stub can
imitate perfectly. The seam is the whole reason the driver is host-testable: L06's tests inject a
stub here, L07 injects the real AVR SPI, and nothing above the seam changes.

---

## The driver interface
`driver::uart::Interface` is the abstract API the application codes against, and it promises five
things: configure the peripheral, write a byte, read a byte, report the status and error state, and
clear errors. Making it abstract is what lets the application, and its tests, be written against a
promise rather than a concrete driver, and it is why the same application later runs unchanged over
the real hardware driver.

`write()` and `read()` are both **non-blocking**. `write()` pushes a byte only if the transmitter has
room, and reports whether it did; `read()` hands back a byte only if one has arrived. That maps
directly onto the FIFO-backed `STATUS` bits from L04 and makes every operation deterministic to test.
Blocking versions, which spin until the peripheral is ready, are a thin convenience built on top, an
exercise in L06 rather than part of the core.

---

## What's ahead
[Appendix B](./b_exercises.md) is the exercises: build the register map, the transport interface,
and the driver interface, then implement that interface once as `driver::uart::Stub`. In L06 you
implement the `Uart` driver over these contracts, using the register protocol, and test it with a
scripted `driver::transport::Stub`.

---

