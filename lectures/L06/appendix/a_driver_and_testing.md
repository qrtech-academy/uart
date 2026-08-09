# Appendix A

## Building and testing the driver
L05 designed the three contracts: the register map, the `driver::transport::Interface` seam, and the
`Interface` the application codes against. L06 puts them to work by implementing the `Uart` driver
over the seam and then proving it with a scripted stub, all on the host. That is the point of the
lecture, so that a byte-order or sequencing bug is caught on your machine in milliseconds, long
before a logic analyzer is involved.

Everything here is written by you; the provided host tests are the check, exactly as the `*_tb.vhd`
benches were on the VHDL side. Appendix B gives the precise build instructions, and this appendix
explains the ideas they rest on.

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
`Uart` implements the L05 `Interface` using the private register read/write core and the register map
you transcribed in L05. Its public methods stay short, because the register bank built in L04 already
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
the register semantics defined in [L04 Appendix A](../../L04/appendix/a_uart_regs.md). The read path
is therefore the delicate one, and it mirrors the register bank's required **read-then-pop**
sequence exactly: establish that data is available, read it without side effects, then issue a
separate command that advances the FIFO.

**Transport injection keeps the driver hardware-independent.** The `Uart` receives a
`driver::transport::Interface` through its constructor and stores it by reference rather than
constructing or owning a concrete SPI implementation, and every register read and write passes
through it. The UART logic therefore depends only on the transport interface, never on AVR registers
or SPI-specific code, and the same `Uart` runs over the stub transport used in this lecture, over any
fake or mock a test cares to write, and over the real AVR SPI transport introduced in L07. Nothing
above the seam changes: the register protocol, the UART behaviour and the public `Interface`
implementation stay identical, and only the injected transport differs.

---

## The scripted stub
To test the driver with no hardware, you build a stub that stands in for the
`driver::transport::Interface` seam. It records every byte the driver sends and plays back bytes you
have queued for it to return, so a test drives the *real* driver and then asserts the exact
transactions it produced. This is the C++ counterpart of a self-checking testbench: the stub is the
wire, scripted.

The stub is a concrete `driver::transport::Interface`. The class is named `driver::transport::Stub`,
it publicly inherits the interface so a `Uart` accepts it wherever the seam is expected, and it
overrides the three seam methods, `begin()`, `transfer()` and `end()`. It is injected into the `Uart`
through the constructor, exactly like the real transport in L07. It lives in
`include/driver/transport/stub.hpp`, beside the interface it implements, so that the host demo in
`source/main.cpp` can drive the driver with no hardware too.

On the `MOSI` side it records what the driver sends. Every byte passed to `transfer()` is appended to
a log the test can read back, and that log is the exact sequence of bytes the driver put on the wire,
so a test asserts against it to check the 5-byte transaction, the command byte and the byte order.
Counting `begin()` and `end()` calls is part of the contract the provided suite asserts on, in eight
of its cases, since that is what confirms each transaction was framed exactly once and that the two
stay balanced.

On the `MISO` side it plays back what the driver reads. The test loads a queue of bytes before the
driver runs, each `transfer()` call returns the next byte from that queue, and once the queue is
empty `transfer()` returns `0x00`. That is how a test makes `readReg` observe a chosen register
value: queue the four bytes, most significant first, that the peripheral would have shifted out. The
suite reaches for that often enough that the stub owes it a word-at-a-time helper, which queues a
32-bit register value most significant byte first, and a reset that clears the queued script between
phases.

The result is a self-checking, hardware-free test. It constructs a `Stub`, constructs a `Uart` over
it, and scripts the responses; it calls the real driver methods under test; and it then asserts on
the stub's recorded bytes and on the driver's return values. No SPI, no AVR and no bench are
involved, and the whole driver is exercised on the host.

---

## What the host tests pin down
Once the driver and stub exist, the provided host suite checks the behaviour that matters:

* **The transactions themselves.** A register read and a register write must produce the exact
  5-byte sequences, with the right command byte and four data bytes **most significant first**. This
  is the byte-order check.
* **Configuring** must write the baud divider first and then enable the peripheral.
* **`write()`** must read `STATUS` and write `TX_DATA` only when there is room, writing nothing when
  there is not.
* **`read()`, on valid data**, must read `STATUS`, then `RX_DATA`, then write `RX_POP`, in that
  order.
* **`read()`, on no data**, must report failure and issue **no** `RX_POP`.
* **The error flags** must read back, and clearing must write zero to them.

The "no pop on empty" and "bytes most significant first" checks are the two that catch the mistakes
which would otherwise only surface on the bench.

---

## What's ahead
[Appendix B](./b_exercises.md) is the exercises: implement the `Uart` driver, the scripted `Stub`,
and a small demo, and get the host suite green. L07 then replaces the stub with `AvrSpi`
over the ATmega328P's real SPI, and nothing above the seam changes.

---

