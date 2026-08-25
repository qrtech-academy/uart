# Appendix B

## Exercises
These exercises supply the half L07 left out: a transport that can be scripted, so the provided host
suite can drive the real `Uart` with no hardware, plus the blocking helpers on top of the
non-blocking core. You write the stub and the helpers; the provided host suite (`make test`) is the
check, and it is the first one the C++ half of the course has been able to run. A small demo
(`main.cpp`) is provided too, listed in full in [Exercise 2.2](#exercise-22---the-provided-demo).

Work in `fw/`. You will add:

```text
include/
    driver/
        uart/
            blocking.hpp
        transport/
            stub.hpp
source/
    main.cpp            (provided; the host demo, copied from Exercise 2.2)
test/
    uart/
        uart_test.cpp   (provided; the host suite, already in the repository)
```

The stub joins the transport interface in `driver::transport` (the demo may use a small `app`
namespace). These conventions apply to `include/` and `source/`, which have to cross-compile for the
ATmega; `test/` and `include/arch/test/` are host-only and never reach avr-gcc, which is why the
provided suites next to them use `<cstdint>`, `std::`, `namespace driver::uart::test` and
`[[nodiscard]]` freely. Follow the same AVR-portable conventions as
[L06](../../L06/appendix/b_exercises.md): `<stdint.h>` and bare `uint8_t` / `size_t` (no `std::`),
nested namespace blocks (not `namespace driver::uart { ... }`), and no `[[nodiscard]]`. Build the
application with `make build` and the tests with `make test`.

The suite is guarded on all four driver headers - `register_map.hpp` and `uart.hpp` from L06 and
L07, `stub.hpp` and `blocking.hpp` from here - so it reports there is nothing to do until the last
of them exists. Adding the two files below is what switches it on.

---

# Exercise Set 1 - The scripted stub

## Exercise 1.1 - `driver::transport::Stub`
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
Two names cost nothing and keep the call sites readable, which is why the L06 UART stub is built the
same way.

Two fixed `uint8_t` buffers with a length each, one for what the driver sent and one for the scripted
replies, are all it takes; no dynamic containers are needed. Both are **linear buffers, not FIFOs**:
the record buffer is a write-only append log the test reads back afterward, and the reply buffer is
read front-to-back through an advancing index. No circular wraparound, no pop-with-shift; just reset
each length, and the read index, to zero at the start of a test.

Keep it dependency-injected: a test constructs a `Stub`, constructs a `Uart` over it, drives the
driver, and then asserts against the `Stub`'s record.

---

---

# Exercise Set 2 - Using the driver

## Exercise 2.1 - Blocking helpers
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

## Exercise 2.2 - The provided demo
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
 *        the ATmega328P (L09), the real transport reports the actual hardware status.
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
call so it completes instead of spinning forever; on the target in L09 the real AVR SPI transport
reports actual hardware status, so the same `main` runs unchanged with no scripting.

Read it, then `make build` and run `./uart_firmware`: it exits cleanly once your `Uart`, `Stub`, and
blocking helpers are correct. The demo is illustration, not a test; the real checking is `make test`.

---

---

## What's ahead
L09 replaces the stub with `AvrSpi`, the real SPI on the ATmega328P, and the driver, the interface,
and the register map all run unchanged over the wire. The suite you just turned green runs unchanged
too, which is the return on putting the seam where L06 put it.

---
