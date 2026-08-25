# Appendix A

## Testing the driver on the host
L07 built the `Uart`: the private register core and every public method of the L06 interface.
Nothing has run it. This lecture supplies the missing half - a transport that can be scripted, and
the provided host suite that drives the real driver over it - so that a byte-order or sequencing bug
is caught on your machine in milliseconds, long before a logic analyzer is involved.

The stub is written by you; the host suite is provided and is the check, exactly as the `*_tb.vhd`
benches were on the VHDL side. Appendix B gives the precise build instructions, and this appendix
explains the ideas they rest on.

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
through the constructor, exactly like the real transport in L09. It lives in
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

The suite is all-or-nothing by design: it is guarded on all four headers existing, so it reports
nothing to do until `register_map.hpp`, `uart.hpp`, `stub.hpp` and `blocking.hpp` are all present.
The first four cases check the *stub*, before any driver case runs, and they are the ones to get
green first. Every `Uart` case reads what the stub was scripted to reply, so a stub bug surfaces as a
driver failure: queue a register value least significant first and the suite reports
`Uart.WriteWhenReadyPushesTxData` red, pointing at L07's `readReg()`, which is correct and unhelpful.

---

## Blocking on top, not inside
`write()` and `read()` are non-blocking because that is what makes them deterministic to test: each
one reports whether it did anything, and a test can drive both outcomes from the stub's script. The
convenience of "send this byte, I'll wait" is real, though, so it is built *over* the interface as
two free functions that spin on the non-blocking core until it succeeds.

Building them that way rather than into the driver keeps the core deterministic and keeps the
spinning where a caller opts into it. They take `Interface&` rather than `Uart&`, so they work over
any implementation - including the `driver::uart::Stub` from L06, which is what lets L10's
`app::EchoNode` be tested with no driver at all underneath it.

---

## What's ahead
[Appendix B](./b_exercises.md) is the exercises: build the scripted `Stub`, get the host suite
green, add the blocking helpers, and run the provided demo. L09 then replaces the stub with `AvrSpi`
over the ATmega328P's real SPI, and nothing above the seam changes.

---
