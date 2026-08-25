# L06 - The Driver's Contracts

## Agenda
This lecture crosses from VHDL to C++, and it stays entirely with *shapes*: the driver stack top to
bottom, and the three abstractions it rests on, before any algorithm is written.

* **The register map in C++**: the seven register indices and the `STATUS` / `CTRL` / `ERROR_FLAGS`
  bits from [Part 2 of the spec](../../protocol/uart_register_protocol.md), transcribed as named
  constants the whole driver shares with `uart_def.vhd`.
* **The transport interface**, `driver::transport::Interface`: a byte-level SPI seam of `begin`,
  `transfer` and `end`. We spend time on why putting that seam at the byte level is exactly what
  makes the driver host-testable.
* **The driver interface**, `driver::uart::Interface`: the abstract, non-blocking API the
  application codes against, being configure, write, read, poll status and clear errors.
* **A first implementation of it**, `driver::uart::Stub`: a test double that plays back scripted
  bytes and records what was written. It needs nothing but the interface, so it can be written the
  moment the interface exists, and it keeps this session from being declarations only.

---

## Objectives
After this lecture, participants should be able to:

* **Transcribe the register map** into `register_map.hpp` as `constexpr` constants, and explain why
  a value here that disagrees with the hardware is a bench-only bug.
* **Design the transport interface** (`driver::transport::Interface`) and say what it buys: the same
  driver over a stub in L08 and over the real AVR SPI in L09, with nothing above the seam changing.
* **Turn the register-level flow into a clean, abstract `Interface`**, and explain why non-blocking
  `write` and `read` map directly onto the FIFO-backed `STATUS` bits from L05.
* **Implement that interface once**, as a `Stub` backed by two linear buffers, and explain what a
  test double has to be faithful about and what it may ignore.

---

## Prerequisites
From Modern Embedded C++ this lecture assumes abstract classes, pure virtual methods, and dependency
injection; Embedded Software Testing is recommended but not required, for why a seam exists and what
a stub sits behind. Read Parts 2 and 3 of the [protocol
spec](../../protocol/uart_register_protocol.md) beforehand.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_driver_stack.md), which lays out the full driver stack and specifies
the three contracts you build here: the register map, the byte-transport seam, and the interface.
These are declarations only; the driver that implements them arrives in L07, and the tests that
check it in L08.

### During the Lecture
We design the three contracts top-down, in the order the design demands rather than the order the
files are written: the interface the application wants, the seam the driver will run over, and the
register map both sides of the wire share. The exercises then implement that driver interface once,
as the UART stub, so the week ends with a concrete class rather than three headers of declarations.
The first `make test` still comes in L08, once both the `Uart` and the stub that scripts it exist.

**The 60 minutes.** Declarations type quickly, so all three headers are written live: there is more
discussion here than typing, and the discussion is the point. The UART stub is the exercise. It is
the first concrete class of the C++ half and about as long as the three headers together, but it is
buffer bookkeeping rather than design, and you now have the interface it must satisfy.

### After the Lecture
Work through the [exercises](./appendix/b_exercises.md): build `driver/uart/register_map.hpp`,
`driver/uart/interface.hpp` and `driver/transport/interface.hpp`, keeping the names the L08 tests
will bind to, then write `driver/uart/stub.hpp` against the interface you just declared.

---

## Evaluation
* Why is the transport seam placed at the raw-byte level rather than exposing `readReg` and
  `writeReg` directly, and what does the byte-level choice let a stub do?
* `write` and `read` are non-blocking and report whether they did anything: which L05 `STATUS` bits
  make that possible, and why is a non-blocking core easier to test than a blocking one?
* The register map is written once in VHDL (`uart_def.vhd`) and once in C++ (`register_map.hpp`):
  what goes wrong if the two disagree, and at which stage would you first notice?

---

## Next Lecture
The contracts get an implementation: the `Uart` driver over the transport interface, and the
register read/write protocol underneath it - the 5-byte transaction, most significant byte first.
The stub that verifies it on the host follows in L08.

---

