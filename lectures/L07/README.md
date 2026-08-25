# L07 - The Driver, Built

## Agenda
L06 designed the contracts; this lecture implements them. Nothing is tested yet - that is L08 - so
the hour goes entirely on the code that has to be right before a test can say so.

* **The register protocol in code**: `readReg()` and `writeReg()` as the 5-byte SPI transactions of
  [Part 3 of the spec](../../protocol/uart_register_protocol.md), each moving its bytes through the
  transport interface most significant byte first.
* **`const` at a hardware boundary**: why `readReg()` is a `const` member driving a non-`const`
  transport, what `const_cast` is doing there, and what it is *not* doing, since `const` never
  propagated through the reference member in the first place.
* **The `Uart` driver** on that core, implementing the L06 `Interface`: `configure`, the
  non-blocking `write`, and the poll, read and separate `RX_POP` that make up the read path.
* **Why the read path is three accesses and not one**: `RX_DATA` is a pure read, `RX_POP` is what
  advances the FIFO, and the L05 register bank is on the other side of the wire enforcing exactly
  that.

---

## Objectives
After this lecture, participants should be able to:

* **Implement `readReg()` and `writeReg()`** as byte sequences that match the protocol spec exactly,
  and explain why the four data bytes go most significant first.
* **Explain what `const` does and does not reach** through a reference member, and justify the
  `const_cast` at the one line where a `const` method starts driving hardware.
* **Implement the `Uart` methods** over that register core, including the poll, read and `RX_POP`
  split, injecting the transport through the constructor.
* **Say what each of the three RX accesses would break** if it were omitted, reordered, or folded
  into the one before it.

---

## Prerequisites
This lecture rests entirely on L06: the register map, the transport interface
(`driver::transport::Interface`), and the driver interface (`driver::uart::Interface`) that the
driver implements. It also assumes the register semantics from L05, since the driver is the other
side of that contract. From Modern Embedded C++ it assumes inheritance, `override` and dependency
injection.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_driver.md), which explains the register read/write core and the
driver built over it. Re-read the **Register Semantics** section of the [protocol
spec](../../protocol/uart_register_protocol.md): every method in this lecture is one half of a
promise the VHDL already keeps.

### During the Lecture
We live-code the register core and then the driver over it:

```bash
make build-cpp        # builds fw/; the suite still reports nothing to do
```

That message is expected and worth pausing on. The provided suite is guarded on four headers, and
two of them - `driver/transport/stub.hpp` and `driver/uart/blocking.hpp` - are L08's, so it stays
switched off for one more lecture. Until then the compiler is the only thing checking this code,
which is exactly why the byte order and the three-access read path are reasoned through rather than
guessed at.

**The 60 minutes.** We type `readReg` and `writeReg`, which are the whole protocol in about sixty
lines and the one place byte order can go wrong, and then `read()`, because the poll, read and
separate pop is the L05 contract showing up on the other side of the wire. The remaining public
methods follow the same shape and are the exercise.

### After the Lecture
Work through the [exercises](./appendix/b_exercises.md): declare `class Uart final : public
Interface`, implement the two private register helpers, and implement every public method of the
interface over them.

---

## Evaluation
* A `writeReg()` sends the four data bytes least significant first: what does the peripheral do with
  the value, and at which point in the course would you first find out?
* `readReg()` is `const` and calls `begin()` / `transfer()` / `end()`, which are not. Explain why
  that compiles with no cast at all, and why the course writes the cast anyway.
* The read path is poll `STATUS`, read `RX_DATA`, write `RX_POP`. Take each of the three away in
  turn and say what the caller observes.

---

## Next Lecture
The driver gets a wire it can be tested against: a scripted `driver::transport::Stub`, the provided
host suite that drives the real `Uart` over it with no hardware in sight, and the blocking helpers
built on top of the non-blocking core.

---
