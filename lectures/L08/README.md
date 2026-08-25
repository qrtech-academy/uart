# L08 - The Driver, Tested

## Agenda
L07 built the driver and nothing ran it. This lecture supplies the wire, scripted, and turns on the
first `make test` the C++ half of the course has had.

* **The scripted stub**: `driver::transport::Stub`, a concrete `driver::transport::Interface` that
  records every byte the driver sends and plays back bytes a test queued for it. It is the C++
  counterpart of a self-checking testbench.
* **Host testing with QAcademy Test**: the provided suite constructs a `Stub`, constructs a `Uart`
  over it, scripts the replies, calls the real driver, and asserts on the exact transactions that
  came out - the 5-byte framing, the command byte, the byte order, and the "no `RX_POP` on empty"
  rule.
* **Testing the test double first**: four `TransportStub` cases run before any driver case, because
  every `Uart` case reads what the stub was scripted to reply, so a stub bug reports itself as a
  driver failure.
* **Blocking `write` and `read`** as thin free functions over the non-blocking core, taking
  `Interface&` rather than `Uart&`, plus a provided demo that exercises the whole API end to end.

---

## Objectives
After this lecture, participants should be able to:

* **Build a scripted stub** and use it to assert the exact transactions the driver produces,
  including the byte order and the "no `RX_POP` on empty" behaviour.
* **Explain what a test double has to be faithful about** and what it may ignore, and why the stub's
  two buffers are linear logs rather than FIFOs.
* **Read a red test and place the bug**, distinguishing a fault in the stub's script from a fault in
  the driver it is scripting.
* **Build blocking helpers over a non-blocking core**, and explain why the spinning lives above the
  driver rather than inside it.

---

## Prerequisites
This lecture needs the `Uart` from L07 and, through it, the three contracts from L06; the driver is
the thing under test, so it has to exist before the suite can say anything about it. From Embedded
Software Testing it assumes unit and component testing with stubs and dependency injection, applied
here to a real driver; that course is recommended but not required.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_testing.md), which explains the scripted stub, what the provided host
suite pins down, and why the blocking helpers sit above the interface rather than inside the driver.
Then read the provided suite itself,
[`fw/test/uart/uart_test.cpp`](../../fw/test/uart/uart_test.cpp): it is the executable specification
of everything L07 wrote, and reading it before writing the stub
tells you exactly which member names the stub owes it.

### During the Lecture
We live-code the stub's two sides, the record and the playback, and then the blocking helpers, which
are two spin loops. The suite comes on the moment the last header exists:

```bash
make build-cpp        # builds fw/, runs its QAcademy Test suite
```

We get the four `TransportStub` cases green first, then watch the `Uart` cases from L07 go green
behind them without a line of driver code changing - which is the point of having built the driver
against an interface rather than against SPI.

**The 60 minutes.** The stub's record side and playback side are typed live, along with
`injectRxWord`, because most-significant-first there is the mirror of most-significant-first in
`readReg` and a mistake in one looks exactly like a mistake in the other. The two blocking helpers
are four lines and get typed too, since the suite is gated on the header existing. `injectRxByte`,
`clearRxData`, the remaining accessors and the provided demo are the exercise.

### After the Lecture
Work through the [exercises](./appendix/b_exercises.md): finish the scripted `Stub`, get the whole
host suite green, add `writeBlocking` / `readBlocking`, then copy in the provided `main.cpp` and run
it.

---

## Evaluation
* Why is the driver tested against a scripted `driver::transport::Stub` rather than the real SPI at
  this stage, and what class of bug does that let you find first?
* `injectRxWord` queues its four bytes least significant first by mistake. Which cases go red, and
  why does the failure point at `readReg()` rather than at the stub?
* The suite counts `begin()` and `end()` calls in eight cases. What would be wrong with a driver
  that passed every byte-sequence assertion but failed those counters?
* Why do `writeBlocking` and `readBlocking` take `Interface&` rather than `Uart&`, and which class
  from L06 does that choice make usable in L10?

---

## Next Lecture
The bottom layer becomes real: the AVR's own `SPCR` / `SPSR` / `SPDR`, `AvrSpi` implementing
`driver::transport::Interface`, and what a freestanding target removes. The driver, the interface,
the register map and this suite all run unchanged.

---
