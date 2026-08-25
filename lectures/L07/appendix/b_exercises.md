# Appendix B

## Exercises
These exercises implement the `Uart` driver over the L06 contracts: the private register core that
turns each access into one 5-byte transaction, and every public method of the interface built on it.
Nothing runs yet. The provided host suite is guarded on four headers, two of which are L08's, so
`make test` still reports there is nothing to do; the check on this work arrives next lecture, and
until then the specification below is the contract.

Work in `fw/`. You will add:

```text
include/
    driver/
        uart/
            uart.hpp
source/
    driver/
        uart/
            uart.cpp
```

The driver lives in the `driver::uart` namespace. These conventions apply to `include/` and
`source/`, which have to cross-compile for the ATmega; `test/` and `include/arch/test/` are host-only
and never reach avr-gcc, which is why the provided suites next to them use `<cstdint>`, `std::`,
`namespace driver::uart::test` and `[[nodiscard]]` freely. Follow the same AVR-portable conventions
as [L06](../../L06/appendix/b_exercises.md): `<stdint.h>` and bare `uint8_t` / `size_t` (no `std::`),
nested namespace blocks (not `namespace driver::uart { ... }`), and no `[[nodiscard]]`. Build with
`make build`.

---

# Exercise Set 1 - The `Uart` driver

## Exercise 1.1 - The class
In `include/driver/uart/uart.hpp`, declare `class Uart final : public Interface`. It holds the
transport as a reference member, `transport::Interface& myTransport`, injected through the
constructor, so that the same driver runs over the L08 stub and over the real SPI in L09; the
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
semantics from L05 make them short.

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
[L05 Appendix A](../../L05/appendix/a_uart_regs.md) contract. **Poll** `STATUS` to learn whether a
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

---

## What's ahead
L08 scripts a transport under this driver: `driver::transport::Stub`, the provided host suite that
drives the real `Uart` over it, and the blocking helpers on top. Every mistake this appendix warns
about - the reversed byte order, the missing `RX_POP`, the bit position used as a mask - is
something a case in that suite exists to catch.

---
