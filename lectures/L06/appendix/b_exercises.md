# Appendix B

## Exercises
These exercises build the driver's three contracts from [Appendix A](./a_driver_stack.md): the
register map, the transport interface, and the driver interface. All three are header-only
declarations, so there is nothing to run yet; L07 implements the driver over them and L08 brings the
first tests. For now the check is simply that each header compiles.

Work in `fw/`. Create the following files:

```text
include/
    driver/
        uart/
            register_map.hpp
            interface.hpp
            stub.hpp
        transport/
            interface.hpp
```

The register map and the driver interface live in the `driver::uart` namespace; the transport
interface lives in `driver::transport`. The names below are the contract the L08 tests bind to, so
keep them as written.

**Write it AVR-portable.** These headers compile on the host (g++) now and, from L09, on the
ATmega328P. **We deliberately skip several modern C++ features here because the AVR toolchain does
not support them**, and the same driver code has to build for both targets, so stay on the subset
that toolchain accepts. The reference point is the AVR/GNU C++ compiler bundled with Microchip
Studio, which is several GCC releases behind a desktop g++; something compiling on your host, or
even on a Linux avr-g++, does not mean it will compile there.

Include `<stdint.h>`, and `<stddef.h>` if you need `size_t`, and use the bare types `uint8_t`,
`uint16_t`, `uint32_t` and `size_t`: the AVR toolchain ships no C++ standard library, so there is
no `<cstdint>` and no `std::` namespace at all, and anything reaching for either will fail.

Write namespaces as nested **blocks**, `namespace driver { namespace uart { ... } }`, because the
compact C++17 form `namespace driver::uart { ... }` does not compile there. Leave out
`[[nodiscard]]`, which it rejects for the same reason. What you can rely on is `noexcept`,
`override`, `final`, `= default`, and pure `= 0`.

---

# Exercise Set 1 - The register map

## Exercise 1.1 - `register_map.hpp`
In `include/driver/uart/register_map.hpp`, transcribe the register map from [Part 2 of the protocol
spec](../../../protocol/uart_register_protocol.md) as `constexpr` constants. Plain `constexpr`, not
`inline constexpr`: inline *variables* are a C++17 feature the AVR toolchain does not have. At
namespace scope `constexpr` already implies internal linkage, so each translation unit gets its own
copy of a compile-time constant, which is exactly what you want and costs nothing. These are the
same values `uart_def.vhd` holds on the other side of the wire; a mismatch is a bug you would only
find on the bench.

### a) Register indices
In a nested namespace `reg`, add one `uint8_t` constant per register index, each one the register's
offset divided by 4: `STATUS = 0`, `CTRL = 1`, `BAUD_DIV = 2`, `TX_DATA = 3`, `RX_DATA = 4`,
`RX_POP = 5` and `ERROR_FLAGS = 6`.

### b) STATUS bit positions
In a nested namespace `status`, add one `uint8_t` **bit-position** constant per `STATUS` bit, meaning
the bit's index rather than a mask: `TX_READY = 0`, `RX_VALID = 1`, `ERROR = 2` and `TX_IDLE = 3`.
These are the same positions `uart_def.vhd` defines, so the two sides agree.

You form a mask by shifting at the use site: `1U << status::TX_READY` tests that bit, and
`status & (1U << status::RX_VALID)` is non-zero when RX has data.

### c) CTRL and error bit positions
In a nested namespace `ctrl`, add `ENABLE = 0` as a `uint8_t` bit position. In a nested namespace
`error`, add `FRAMING = 0`, `PARITY = 1` and `OVERRUN = 2`, all `uint8_t` bit positions. The VHDL
package also defines parity, stop-bit and interrupt-mask positions in `CTRL`; this driver does not
use them yet, so it does not declare them.

Positions rather than masks keep the C++ constants identical to the VHDL `uart_def.vhd`, which also
stores positions, and the one-line `1U << pos` at each use site is explicit about which bit you mean.

---

# Exercise Set 2 - The transport interface

## Exercise 2.1 - `driver::transport::Interface`
In `include/driver/transport/interface.hpp`, design an abstract class `driver::transport::Interface`
representing a byte-level SPI transport. It exchanges raw bytes over one transaction and knows
nothing about registers. All methods except the destructor shall be pure virtual (`= 0`).

### a) Destructor
Add a destructor that is virtual, marked `noexcept`, and implemented using `= default`.

### b) Begin a transaction
Add a pure virtual method `begin()` that starts a transaction by pulling `SS` low. It takes no
parameters, returns nothing, and cannot throw exceptions.

### c) Exchange one byte
Add a pure virtual method `transfer()` that exchanges a single byte in full duplex. It takes one
parameter of type `uint8_t`, the byte to send, returns the `uint8_t` received at the same time, and
cannot throw exceptions.

### d) End a transaction
Add a pure virtual method `end()` that ends the transaction by releasing `SS`. It takes no
parameters, returns nothing, and cannot throw exceptions.

---

# Exercise Set 3 - The driver interface

## Exercise 3.1 - `Interface`
In `include/driver/uart/interface.hpp`, design an abstract class `driver::uart::Interface`, the
driver's public API. All methods except the destructor shall be pure virtual.

### a) Destructor
Add a destructor that is virtual, `noexcept`, and `= default`.

### b) Configure
Add a pure virtual method `configure()` that sets the baud divider and enables the peripheral. It
takes one parameter of type `uint16_t`, the baud divider, returns nothing, and cannot throw
exceptions.

### c) Write a byte
Add a pure virtual method `write()` that attempts to send one byte. It takes one parameter of type
`uint8_t`, returns `true` if the byte was accepted or `false` if the transmit FIFO was full, and
cannot throw exceptions.

### d) Read a byte
Add a pure virtual method `read()` that attempts to receive one byte. It takes a reference to a
`uint8_t` where the received byte will be stored, returns `true` if a byte was received and `false`
otherwise, and cannot throw exceptions.

### e) Status and errors
Add three more pure virtual methods, none of which throws. `status()` returns the raw `STATUS`
register as a `uint32_t`, takes no parameters, and does not modify the object (`const`).
`errorFlags()` returns the raw `ERROR_FLAGS` register as a `uint32_t`, also taking no parameters and
also `const`. `clearErrors()` clears the error flags, takes no parameters, and returns nothing.

---

# Exercise Set 4 - The UART stub

## Exercise 4.1 - `driver::uart::Stub`
The three headers above are all declarations. This one is the first concrete class of the C++ half,
and it is worth writing now rather than later, because it needs nothing except the interface you
just declared: a **UART stub**, a `driver::uart::Interface` a test can drive.

It plays back scripted bytes on `read()` and records the bytes an application `write()`s, so a test
can queue input, run something over it, and check what came out. It is the same idea as the
`driver::transport::Stub` you write in L08, one layer up: that one fakes the wire under the driver,
this one fakes the driver under an application. Write it in `include/driver/uart/stub.hpp`,
header-only, in the `driver::uart` namespace, in the same AVR-portable style as everything else here;
it holds no dynamic memory, so it compiles for the target as well as the host.

Because a UART is a byte stream, both directions are **FIFO**: bytes are received and recorded in the
order they arrive. But a test queues a bounded number of bytes and reads them once, so the storage is
two plain **linear buffers** with no wraparound to reason about: two fixed `uint8_t` arrays, each
with a length. The **RX** buffer is read front-to-back through an advancing index, so `read()` hands
back the byte at the index and advances it, and the length is how many bytes were queued. The **TX**
buffer is a write-only append log, so `write()` appends one byte and bumps the length, and the test
reads the whole log back afterward.

**Member variables**, using a fixed capacity `OurBufLen` and `uint8_t` throughout, with no `size_t`.
`myRxBuf[OurBufLen]`, with `myRxLen` and `myRxIdx`, holds the scripted bytes to receive and tracks
how far `read()` has advanced through them. `myTxBuf[OurBufLen]`, with `myTxLen`, holds the bytes the
application has sent, appended in order.

The third is `bool& myStop`, a reference to a caller-owned flag, set `true` when `read()` reaches the
end of the RX buffer. That one needs a word of explanation this early: in L10 you write an
application whose `run(const bool& stop)` loops until the flag is set, and a single-threaded test has
no other way to end it. The stub feeds every scripted byte and then, once the input is exhausted,
asks the loop to stop. Because it is a reference member, copy and move are deleted, as is the default
constructor, since you need a stop flag to build one.

**Methods**, the six from `driver::uart::Interface` plus scripting helpers. The constructor,
`Stub(bool& stop)`, is `explicit`, stores the stop reference, and leaves both buffers empty.
`configure(uint16_t)` does nothing, since the stub has no baud rate to set. `write(uint8_t byte)`
appends `byte` to `myTxBuf` if there is room and returns `true`, as a UART with room in its TX FIFO
would, and returns `false` if the buffer is full. `read(uint8_t& byte)` hands back
`myRxBuf[myRxIdx++]` and returns `true` when `myRxIdx < myRxLen`, and otherwise sets `myStop` to
`true` and returns `false`; that empty-case flag is the loop's off switch. `status()`, `errorFlags()`
and `clearErrors()` are trivial, returning `0` or doing nothing, because the applications tested this
way drive the UART through `read()` and `write()` rather than the status register.

Three helpers exist for the tests. `injectRxByte(uint8_t byte)` appends one scripted byte to
`myRxBuf`, returning `false` if it is full, and is called once per byte the application should
receive. `txBuf()` and `txLen()` return a pointer to the recorded TX bytes and how many there are, so
a test reads `txBuf()[i]` for `i < txLen()` in the order they were sent. And `reset()` zeroes both
lengths, the read index and the stop flag, so the stub can be reused across tests.

Nothing exercises it yet, which is the honest state of a test double written before the thing it
doubles for. It compiles, and in L10 it becomes the entire test harness for `app::EchoNode`.

---

## What's ahead
In L07 you implement `driver::uart::Uart`, which inherits this interface and drives it through the
register protocol over a `driver::transport::Interface`; L08 then writes the scripted
`driver::transport::Stub` and gets the host tests that check it green. The UART stub written here
waits until L10, where it becomes the test harness for `app::EchoNode`.

---

