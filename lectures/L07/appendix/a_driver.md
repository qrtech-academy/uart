# Appendix A

## Building the driver
L06 designed the three contracts: the register map, the `driver::transport::Interface` seam, and the
`Interface` the application codes against. L07 puts them to work by implementing the `Uart` driver
over the seam: the private register core that turns each access into one 5-byte transaction, and the
public methods built on it. Proving it, with a scripted stub and the provided host suite, is L08.

Everything here is written by you. Appendix B gives the precise build instructions, and this
appendix explains the ideas they rest on. Nothing is run yet: the suite that grades this code needs
the stub from L08 before it will do anything, which is why the byte order and the ordering of the
three RX accesses are worth getting right by reasoning rather than by trial.

---

## The register protocol: reading and writing a register
The driver's private core is two operations that turn each register access into one **5-byte
transaction**, as defined in Part 3 of the specification. Both move their bytes through the injected
`driver::transport::Interface`.

Every transaction is exactly five bytes: one command byte, then four data bytes. The command byte
carries the operation type in bit 7, `0` for a register read and `1` for a register write, the
register index in the low nibble, and any unused bits set as the protocol requires.

A **register read** sends a command byte with the write bit clear and the register index in the low
nibble, then exchanges four dummy bytes after it. Whatever came back while the command byte was going
out is ignored; the four bytes returned during the dummy exchanges are the answer, and they assemble
into a 32-bit value with the first returned byte as the most significant and the last as the least
significant. This relies on the peripheral's latch-once-then-shift-out behaviour: the register value
is captured at the end of the command byte, once the address is known, so all four returned bytes
belong to the same captured value.

A **register write** sends a command byte with the write bit set and the register index in the low
nibble, then splits the 32-bit value into four bytes and sends them most significant first, least
significant last. The whole command and value goes out as one 5-byte transaction, and the peripheral
commits the new register value once the fifth byte has been received.

Both operations go through `driver::transport::Interface`, so the driver never depends on a
particular SPI or hardware implementation. Each transmitted byte passes through the injected
transport, and the byte each exchange returns is what the read operation collects. That separation is
what makes the register protocol easy to test against a fake transport.

**Byte order is critical.** Both reads and writes are most-significant-byte-first. A read must
reconstruct the result in the same order the peripheral shifts it out, and a write must split the
value in the order the peripheral expects; reverse the bytes and you have a different 32-bit value,
even though the same four bytes crossed the wire. It is the detail most likely to be implemented
incorrectly, and one of the tests exists specifically to catch it, using a value whose reversed byte
sequence is visibly different to the hardware.

---

## The driver
`Uart` implements the L06 `Interface` using the private register read/write core and the register map
you transcribed in L06. Its public methods stay short, because the register bank built in L05 already
provides most of the UART semantics.

**Writing one byte** reads `STATUS`, checks whether the transmitter can accept another byte, and if
it can, writes the byte to `TX_DATA` and reports that it was accepted. If it cannot, the driver
writes nothing and reports that the operation could not be completed yet. The driver never manages
the transmit FIFO directly; it watches the ready flag and writes the next byte when permitted.

**Reading one byte** reads `STATUS` and checks whether a valid byte is waiting in the receive FIFO.
If one is, it reads the byte from `RX_DATA`, keeps it as the result, performs a separate write to
`RX_POP`, and returns the byte to the caller. If no byte is available it neither reads `RX_DATA` nor
writes `RX_POP`, and simply reports that nothing was available.

That receive sequence is deliberately three steps: poll `STATUS`, read `RX_DATA`, write `RX_POP`.
Reading `RX_DATA` is a pure read, returning the byte at the front of the FIFO without removing it, so
repeated reads return the same byte until an explicit pop happens. Writing `RX_POP` is what advances
the FIFO, removing the current byte only after it has been read successfully and making the next
queued byte visible through `RX_DATA`.

The order matters in every direction. Polling first prevents the driver from reading an empty FIFO;
reading before popping ensures the current byte is not discarded; popping afterwards ensures the
next call observes the next byte. Omit the pop and the same byte comes back indefinitely, pop before
the read and the current byte is skipped, and hiding the pop inside the `RX_DATA` read would violate
the register semantics defined in [L05 Appendix A](../../L05/appendix/a_uart_regs.md). The read path
is therefore the delicate one, and it mirrors the register bank's required **read-then-pop**
sequence exactly: establish that data is available, read it without side effects, then issue a
separate command that advances the FIFO.

**Transport injection keeps the driver hardware-independent.** The `Uart` receives a
`driver::transport::Interface` through its constructor and stores it by reference rather than
constructing or owning a concrete SPI implementation, and every register read and write passes
through it. The UART logic therefore depends only on the transport interface, never on AVR registers
or SPI-specific code, and the same `Uart` runs over the stub transport L08 scripts under it, over any
fake or mock a test cares to write, and over the real AVR SPI transport introduced in L09. Nothing
above the seam changes: the register protocol, the UART behaviour and the public `Interface`
implementation stay identical, and only the injected transport differs.

---

---

## What's ahead
[Appendix B](./b_exercises.md) is the exercises: implement the `Uart` class, the private register
core, and every public method of the L06 interface. L08 then scripts a transport under it and turns
the provided host suite green, and L09 replaces that stub with `AvrSpi` over the ATmega328P's real
SPI, with nothing above the seam changing.

---
