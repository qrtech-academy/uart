# Appendix B

## Exercises
These exercises implement the `Uart` driver over the L05 contracts and build a scripted stub to test
it with no hardware. This is the C++ counterpart of authoring an implementation and running it
against a self-checking bench: you write the driver, the stub, and the blocking helpers, and the
provided host suite (`make test`) is the check. A small demo (`main.cpp`) is provided too, listed in
full in [Exercise 3.2](#exercise-32---the-provided-demo).

Work in `fw/`. You will add:

```text
include/
    driver/
        uart/
            uart.hpp
            blocking.hpp
        transport/
            stub.hpp
source/
    driver/
        uart/
            uart.cpp
    main.cpp            (provided; the host demo, copied from Exercise 3.2)
test/
    uart/
        uart_test.cpp   (provided; the host suite, already in the repository)
```

The driver lives in the `driver::uart` namespace; the stub joins the transport interface in
`driver::transport` (the demo may use a small `app` namespace). These conventions apply to
`include/` and `source/`, which have to cross-compile for the ATmega; `test/` and
`include/arch/test/` are host-only and never reach avr-gcc, which is why the provided suites next to
them use `<cstdint>`, `std::`, `namespace driver::uart::test` and `[[nodiscard]]` freely. Follow the
same AVR-portable conventions as [L05](../../L05/appendix/b_exercises.md): `<stdint.h>` and bare
`uint8_t` / `size_t` (no `std::`), nested namespace blocks (not `namespace driver::uart { ... }`),
and no `[[nodiscard]]`. Build the application with `make build` and the tests with `make test`.

---

# Exercise Set 1 - The `Uart` driver

## Exercise 1.1 - The class
In `include/driver/uart/uart.hpp`, declare `class Uart final : public Interface`. It holds the
transport as a reference member, `transport::Interface& myTransport`, injected through the
constructor, so that the same driver runs over the stub here and over the real SPI in L07; the
constructor therefore takes a `driver::transport::Interface&` and stores it. Delete copy and move,
since a reference member cannot be reassigned and the intent is worth making explicit. Declare each
`Interface` method with `override`, keeping the `noexcept` and `const` qualifiers from the interface
exactly.

Put the two private register helpers (Exercise 1.2) in the private section. Implement the bodies in
`source/driver/uart/uart.cpp`.

## Exercise 1.2 - The register access core (private)
Add two private helpers. They are the **only** methods that touch `myTransport`, and each performs
one 5-byte SPI transaction from [Part 3 of the protocol
spec](../../../protocol/uart_register_protocol.md).

`readReg(index)` returns a register's 32-bit value. It begins the transaction with
`myTransport.begin()`, then sends the command byte, which is the register index with the write bit
clear (bit 7 = 0), using `myTransport.transfer(command)` and ignoring the byte that comes back, since
the reply to the command byte is meaningless. It then clocks out the four data bytes by calling
`myTransport.transfer(0x00)` four times, sending dummy zeros, and assembles the four returned bytes
into the result **most significant byte first**, so the first byte back is bits 31-24. Finally it
ends the transaction with `myTransport.end()` and returns the assembled value.

Every byte here moves through the injected `myTransport`, using `myTransport.transfer()`, the raw
duplex SPI exchange. Do **not** call the driver's own `write()`: that is the public "send a UART
byte" operation, a different thing entirely, and calling it here would recurse.

`writeReg(index, value)` commits a 32-bit value to a register. It begins the transaction, sends the
command byte, which is the register index with the write bit set (bit 7 = 1), via
`myTransport.transfer(command)` while ignoring the reply, then sends the four bytes of `value`
**most significant first** (bits 31-24 first), each with `myTransport.transfer(...)` and each reply
ignored, and ends the transaction.

Make `readReg` a `const` member: it does not modify the `Uart` object; it exchanges bytes through
the transport, whose state is its own. `writeReg` need not be `const`. Marking `readReg` const is
exactly what lets `status()` and `errorFlags()` be `const`.

Most significant first, in both helpers, is the detail the byte-order test exists to catch. A
reversed value is a different value to the hardware.

### Reaching a non-const transport from a `const` method (`const_cast`)
`readReg` is `const`, but the transport's `begin()` / `transfer()` / `end()` are **not**: driving SPI
is an action with side effects, not an observation. So a `const` method that has to perform a
register read must reach a non-const operation, and this course writes that reach out explicitly:

```cpp
uint32_t Uart::readReg(uint8_t addr) const noexcept
{
    auto& transport = const_cast<transport::Interface&>(myTransport);
    transport.begin();
    // ... transport.transfer(...) ...
    transport.end();
    // ...
}
```

Read that cast carefully, because it is doing less than it looks like it is doing. **The enclosing
`const` never reached the transport in the first place.** `myTransport` is a *reference* member, and
`const` does not propagate through a reference: inside a `const` method, `myTransport` still names a
plain `transport::Interface&`, so the compiler would accept `myTransport.begin()` with no cast at
all. The cast yields the type the expression already had. In general, `const_cast` is what you reach
for when a logically-`const` method (an observer such as `status()`) has to invoke a non-const
operation underneath, and you have decided the method should stay `const` to its callers. It is a
deliberate compromise, and worth understanding precisely.

The alternatives are marking the method non-`const`, which is honest but then means `status()` cannot
be `const`, or using a `mutable` member, which is right for a cache and awkward for a reference.
`const_cast` keeps the public `const` promise while admitting that the implementation must drive
something underneath. So why write a cast the compiler does not ask for? Because it makes the intent
explicit at the one line where a `const` method starts driving hardware, and because it becomes
genuinely *required* the moment the transport is held differently - by value, or behind a
`const`-propagating handle - at which point the object's `const` does reach the member and the calls
stop compiling. Writing it now makes that change a one-word edit rather than a redesign. Be clear
which of the two you are relying on: here it is documentation, not necessity.

The one hard rule is to cast away `const` only on an object that is not actually `const`.
`myTransport` refers to a real, non-`const` transport the caller owns, so driving it is defined
behaviour; casting away `const` on a genuinely `const` object and then mutating it is undefined
behaviour.

## Exercise 1.3 - The public methods
Implement each `Interface` method in terms of the two helpers and the register map. The register
semantics from L04 make them short.

`configure(baudDiv)` sets the baud rate first and enables afterwards: `writeReg(BAUD_DIV, baudDiv)`,
then `writeReg(CTRL, 1U << ENABLE)`. Note the shift: `ENABLE` is a bit *position*, as every
constant in the register map is, so writing it directly would send `0` and clear the register
rather than set bit 0.

`write(byte)` reads `STATUS`; if `TX_READY` is set it calls `writeReg(TX_DATA, byte)` and returns
`true`, and otherwise it writes nothing and returns `false`.

`read(byte&)` reads `STATUS`; if `RX_VALID` is set it reads `RX_DATA` into the out-parameter, then
writes `writeReg(RX_POP, 1)` to advance the FIFO, and returns `true`. If `RX_VALID` is clear it
returns `false` and issues **no** `RX_POP`.

That success path is three distinct register accesses, in this order, which is the
[L04 Appendix A](../../L04/appendix/a_uart_regs.md) contract. **Poll** `STATUS` to learn whether a
byte is even available. **Read** `RX_DATA`, which is a *pure read*: it returns the front byte but
does **not** remove it from the FIFO. Then **pop** by writing `RX_POP`, a separate write that
discards the front byte so the next call sees the next one.

Because `RX_DATA` does not pop on its own, the `RX_POP` write is not optional. If you leave it out,
whether by forgetting it or by assuming the read already advanced the FIFO, the front byte is never
discarded, so every following `read` polls `RX_VALID`, finds it still set, re-reads `RX_DATA`, and
returns the **same byte forever**. Popping *before* the read is the opposite mistake: it discards the
current byte unread and skips data.

The last three are one-liners. `status()` returns `readReg(STATUS)`, `errorFlags()` returns
`readReg(ERROR_FLAGS)`, and `clearErrors()` calls `writeReg(ERROR_FLAGS, 0)`.

---

# Exercise Set 2 - The scripted stub

## Exercise 2.1 - `driver::transport::Stub`
In `include/driver/transport/stub.hpp`, build a header-only `driver::transport::Stub` that
implements `driver::transport::Interface` so the driver can be tested with no hardware. It is the
wire, scripted, and it has three jobs.

The provided test suite binds to this stub by name, so the names below are part of the exercise
rather than suggestions: a stub with the right behaviour but different member names will not
compile against `test/uart/uart_test.cpp`. It needs a default constructor, since every test builds
one with `transport::Stub stub{};`.

That suite opens with four `TransportStub` cases that check the stub itself, before any driver case
runs. They are there because every `Uart` case reads what the stub was scripted to reply, so a stub
bug surfaces as a *driver* failure: queue the four bytes least significant first, for instance, and
the suite reports `Uart.WriteWhenReadyPushesTxData` red, pointing at `readReg()`, which is correct.
Get the `TransportStub` cases green first and the failures below are genuinely yours.

It must **record** every call. Append each byte passed to `transfer()` to a fixed-size `uint8_t`
buffer with a running length, where a capacity of 100 bytes is plenty for these tests. Expose that
record through `txLen()`, returning the number of bytes captured, and `txByte(index)`, returning
the byte at a position and `0` for an index past the end. Both must be **`const`**, because the
tests inspect the stub through a `const transport::Stub&`. Keep two `uint16_t` counters as well,
one bumped by `begin()` and one by `end()`, exposed as `beginCalls()` and `endCalls()`, also
`const`. These are not optional: the suite asserts on them in eight separate cases, because they
are what proves a transaction was framed exactly once and that the two stay balanced.

It must **play back** bytes on `transfer()`, returning the next byte from a preloaded response
buffer tracked by an index, and returning `0x00` once that buffer is exhausted. This is the `MISO`
the driver reads.

And it must offer helpers to script that response. `injectRxByte(uint8_t)` queues a single byte, and
`injectRxWord(uint32_t)` queues a whole register value **most significant first**, so that a
`readReg` sees exactly that value. `clearRxData()` resets the reply buffer and its index, so one
test can script several reads.

Give the two a *different name* rather than overloading one name on width. An integer literal
converts equally well to `uint8_t` and to `uint32_t`, so an overload pair would make
`stub.injectRx(0x41)` ambiguous and force every call site to spell out the type of its argument.
Two names cost nothing and keep the call sites readable, which is why the L08 UART stub is built the
same way.

Two fixed `uint8_t` buffers with a length each, one for what the driver sent and one for the scripted
replies, are all it takes; no dynamic containers are needed. Both are **linear buffers, not FIFOs**:
the record buffer is a write-only append log the test reads back afterward, and the reply buffer is
read front-to-back through an advancing index. No circular wraparound, no pop-with-shift; just reset
each length, and the read index, to zero at the start of a test.

Keep it dependency-injected: a test constructs a `Stub`, constructs a `Uart` over it, drives the
driver, and then asserts against the `Stub`'s record.

---

# Exercise Set 3 - Using the driver

## Exercise 3.1 - Blocking helpers
The interface's `write()` and `read()` are non-blocking by design. Build the thin blocking
convenience on top, in a new header `include/driver/uart/blocking.hpp`, as free functions in the
`driver::uart` namespace. Keep the same AVR-portable style as the rest of the driver (`<stdint.h>`
and bare types, nested namespace blocks). Both take `Interface&`, not `Uart&`, so they work over any
implementation; `uart.write` / `uart.read` dispatch to the concrete driver at runtime.

### a) Write a byte, blocking
Add a free function `writeBlocking()` that sends one byte, waiting until the transmitter accepts it.
It takes a `driver::uart::Interface&`, the driver, and a `uint8_t`, the byte to send; it spins on
`uart.write(byte)` until that returns `true` and then returns nothing. Mark it `inline`, since it is
defined in a header and that avoids a one-definition-rule violation once more than one file includes
it, and mark it `noexcept`.

### b) Read a byte, blocking
Add a free function `readBlocking()` that receives one byte, waiting until one is available. It takes
a `driver::uart::Interface&`, the driver, and a reference to a `uint8_t` where the received byte is
stored; it spins on `uart.read(byte)` until that returns `true` and then returns nothing. It is
`inline` and `noexcept` for the same reasons.

Each is a one-line spin loop, so header-only `inline` functions are all you need; no `.cpp`. They
belong above the driver, not inside it: the core stays deterministic and testable, and the spinning
lives where a caller opts into it.

## Exercise 3.2 - The provided demo
Use this test program to test communication end to end. It is **provided** (like the host suite);
you do not write it. Create `source/main.cpp` and copy it in as it stands:

```cpp
/**
 * @brief Application entry point.
 */
#include <stdint.h>

#include "driver/transport/stub.hpp"
#include "driver/uart/blocking.hpp"
#include "driver/uart/register_map.hpp"
#include "driver/uart/uart.hpp"

using namespace driver;

/**
 * @brief Application entry point.
 *
 *        On the host, the demo uses a scripted transport::Stub because no real UART is available.
 *        It reports TX ready and returns one received byte so the blocking calls can complete. On
 *        the ATmega328P (L07), the real transport reports the actual hardware status.
 *
 *        Each register read transfers one command byte followed by four data bytes, so scripted
 *        responses begin with a command-phase placeholder. Because writes also consume scripted
 *        bytes, each response is installed immediately before use and clearRxData() resets the
 *        script between phases.
 *
 * @return 0 on termination of the program.
 */
int main()
{
    constexpr uint16_t baudDiv{27U};
    constexpr uint8_t txByte{0x7FU};
    constexpr uint8_t dummyCmd{0U};

    constexpr uint32_t rxData{txByte};
    constexpr uint32_t txReady{static_cast<uint32_t>(1U << uart::status::TX_READY)};
    constexpr uint32_t rxValid{static_cast<uint32_t>(1U << uart::status::RX_VALID)};

    transport::Stub transport{};
    uart::Uart uart{transport};
    uart.configure(baudDiv);

    // Report TX ready, then send a byte.
    transport.injectRxByte(dummyCmd);
    transport.injectRxWord(txReady);
    uart::writeBlocking(uart, txByte);

    // Report RX valid and hand back the byte, then receive it.
    transport.clearRxData();
    transport.injectRxByte(dummyCmd);
    transport.injectRxWord(rxValid);
    transport.injectRxByte(dummyCmd);
    transport.injectRxWord(rxData);

    uint8_t rxByte{};
    uart::readBlocking(uart, rxByte);
    return 0;
}
```

It shows the API end to end: it constructs a `Uart` over a `driver::transport::Stub`, `configure()`s
it, then uses your `writeBlocking` / `readBlocking` to send a byte and receive one back. Because the
blocking calls spin until the transport reports ready, the demo scripts the stub just before each
call so it completes instead of spinning forever; on the target in L07 the real AVR SPI transport
reports actual hardware status, so the same `main` runs unchanged with no scripting.

Read it, then `make build` and run `./uart_firmware`: it exits cleanly once your `Uart`, `Stub`, and
blocking helpers are correct. The demo is illustration, not a test; the real checking is `make test`.

---

## What's ahead
L07 replaces the stub with `AvrSpi`, the real SPI on the ATmega328P, and the driver, the
interface, and the register map all run unchanged over the wire.

---

