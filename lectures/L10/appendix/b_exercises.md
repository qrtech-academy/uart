# Appendix B

## What you are building

### The `app::EchoNode` application
`EchoNode` is the application that finishes the course: it receives a byte over the UART and sends it
straight back. On the bench, what you type in the terminal comes back to you, having crossed every
layer the course built. The application itself is tiny, because all the hard work is already done and
tested underneath it: the driver, the transport, the peripheral. `EchoNode` just spends that stack.

The important idea is that `EchoNode` is **software you write and host-test before you touch the
bench**. It depends only on `driver::uart::Interface`, not on `Uart`, `AvrSpi`, or any hardware, so
you build it, test it against the UART stub, and only *then* flash it and bring it up (the last rung
of [Appendix C](./c_bringup.md)). By the time it reaches the bench, its logic is already proven; the
only thing the bench adds is the wiring. This is the same discipline the whole course runs on -
host-test behind the interface seam first, hardware last - applied one level up, to the application.

This appendix **describes** `EchoNode`; you write it yourself. The UART stub it is tested against
was written in L06, as soon as the interface it implements existed.

---

### The application seam: `app::Interface`
Applications sit behind their own interface, `app::Interface`, exactly as drivers sit behind
`driver::uart::Interface`. It declares a single operation, `run(const bool& stop)`, which runs the
application until `stop` becomes `true`. `main()` holds an `app::Interface&` and calls `run()`, so it
neither knows nor cares which application it runs; swapping `EchoNode` for another is a one-line
change in `main()`.

`stop` is a `const bool&`, a flag the application only *reads*, hence the `const`, owned by whoever
started it. Setting it `true` asks the application to return from `run()`, which is a clean shutdown
and, in a test, the way the loop is ended. It is a plain `bool` rather than a `std::atomic`, because
avr-libc is freestanding and ships no `<atomic>`, and on the single-core ATmega a byte read is
already indivisible.

---

### `app::EchoNode`
`EchoNode` implements `app::Interface`. Write it as `include/app/echo_node.hpp` (the declarations)
and `source/app/echo_node.cpp` (the definitions), in the `app` namespace, in the same AVR-portable
style as the driver (`<stdint.h>` and bare types, nested namespace blocks, no `[[nodiscard]]`). It
is `final`, non-copyable, and non-movable.

**Member variable.** There is one: `driver::uart::Interface& myUart`, the UART driver to echo over,
injected through the constructor and held by reference. That reference is what lets the *same* class
run over the concrete `Uart` on hardware and over the UART stub in a test, with no change. Because it
is a reference it is set once at construction and never rebound, which is also why copy and move are
deleted: a reference member cannot be reassigned, the same reason `Uart` deletes them.

**Methods.** The constructor, `EchoNode(driver::uart::Interface& uart)`, is `explicit` and
`noexcept`. It takes the driver to echo over and stores it in `myUart`, and it does no I/O, since
construction only wires the dependency and therefore cannot fail.

`run(const bool& stop)` is the application loop, `noexcept`, overriding `app::Interface::run()`. It
repeats until `stop` is `true`, and on each pass it checks `stop`, asks `myUart` for a byte with the
**non-blocking** `read()`, and, if one arrived, echoes it straight back with `writeBlocking()`.

The receive is a poll rather than `readBlocking()` on purpose. A blocking read would wait forever for
a byte and never look at `stop` again, so the loop could not be stopped, and a test of it would hang.
Polling `read()` returns to the top of the loop every pass to re-check `stop`, which is exactly what
lets a caller, or the test, end it. The echo write may block, using `writeBlocking()`, because the
byte is already in hand and simply has to go out.

---

### Host-testing it, before any hardware
Because `EchoNode` depends only on `driver::uart::Interface`, you test it against the **UART stub**
you wrote back in [L06](../../L06/appendix/b_exercises.md), the moment that interface existed: no
`Uart`, no transport, no FPGA. This is the session it finally earns its keep. The trick that makes
`run()` return in a test is the `stop` flag: the stub sets `stop` to `true` the moment its scripted
RX runs out, so `run()` echoes every queued byte and then ends on the next check. The test queues
the input, constructs the `EchoNode` over the stub, calls `run(stop)`, and asserts the stub's
recorded TX equals what it queued, in order. The suite lives in `test/app/echo_node_test.cpp` and,
like the other host tests, may use full modern C++; run it with `make test`.

That termination trick is also a check on your implementation: because it depends on `run()` polling
`read()` and re-checking `stop`, a `run()` that blocked in `readBlocking()` would hang the test - the
test telling you the loop is not actually stoppable.

---

### On the bench
Nothing about the class changes for hardware. The application `main()` on the Nano constructs the
real stack under the same interface - an `AvrSpi`, a `Uart` over it, `configure()`d for 115200 8N1,
then an `EchoNode` over the `Uart` - and calls `run()` with a `stop` flag it leaves `false`, so the
node echoes forever. That is the last rung of the [bring-up ladder](./c_bringup.md): the exact class
you host-tested, now echoing real characters typed in the terminal, over real SPI, through your own
VHDL peripheral.

---

## Exercise 1 - `app::EchoNode`
**a)** Write `include/app/interface.hpp` first - the `app::Interface` seam described above: a virtual
`noexcept` destructor that is `= default`, and the single pure virtual `run(const bool& stop)
noexcept`. Then write `include/app/echo_node.hpp` and `source/app/echo_node.cpp` from the description
above, the `myUart` member, the constructor, `run(const bool& stop)`, and the deleted copy and move,
so that `EchoNode` implements `app::Interface`. Run `make test` and confirm the echo test passes with
no hardware.

**b)** The test drives `run()` with the stub, which stops once its scripted RX is exhausted, queuing
the bytes `0x00`, `0x41`, and `0xFF`. Add a case that queues **nothing** and confirm `run()` returns
immediately, having sent nothing. Which implementation mistake is this the only case that catches?

**c)** Method `run(const bool& stop)` is the unit under test, ended by the flag. Explain why `run()`
must poll the non-blocking `read()` rather than call `readBlocking()`, and connect it to why `stop`
is passed by reference (and read every pass) rather than returned or checked once.

**d)** Change `EchoNode` to echo each byte back **uppercased** (leave non-letters alone), and update
the test. Keep the transformation inside `run()`; the point is that the application layer is exactly
where such policy belongs, above a driver that only moves bytes.

---

## What's ahead
With `EchoNode` written and host-tested, [Appendix C](./c_bringup.md) is the bench: flash it and
climb the bring-up ladder to watch it echo in real hardware, then trace one byte through every layer
of the stack the course built.

---

