# L06 - The Driver, Built and Tested

## Agenda
L05 designed the contracts; this lecture implements them.

* **The register protocol in code**: `readReg()` and `writeReg()` as the 5-byte SPI transactions of
  [Part 3 of the spec](../../protocol/uart_register_protocol.md), each moving its bytes through the
  transport interface most significant byte first.
* **The `Uart` driver** on that core, implementing the L05 `Interface`: configure, the non-blocking
  `write`, and the poll, read and separate `RX_POP` that make up the read path.
* **Host testing with QAcademy Test**, using a scripted `driver::transport::Stub` that records what
  the driver sends and plays back what it should read, so the whole driver is verified with no
  hardware in sight.
* **Blocking `write` and `read`** as thin free functions over the non-blocking core, and a small
  demo that exercises them.

---

## Objectives
After this lecture, participants should be able to:

* **Implement `readReg()` and `writeReg()`** as byte sequences that match the protocol spec exactly,
  and explain why the four data bytes go most significant first.
* **Implement the `Uart` methods** over that register core, including the poll, read and `RX_POP`
  split, injecting the transport through the constructor.
* **Build a scripted stub** and use it to assert the exact transactions the driver produces,
  including the byte order and the "no `RX_POP` on empty" behaviour.

---

## Prerequisites
This lecture rests entirely on L05: the register map, the transport interface
(`driver::transport::Interface`), and the driver interface (`driver::uart::Interface`) that the
driver implements. From Modern Embedded C++ it assumes inheritance, `override` and dependency
injection; Embedded Software Testing is recommended but not required, for unit and component testing
with stubs, applied here to a real driver.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_driver_and_testing.md), which explains the register read/write core,
the driver built over it, the scripted stub, and what the provided host suite pins down.

### During the Lecture
We live-code the register core and then one method of the driver over the seam, running the host
tests as they come green:

```bash
make build-cpp        # builds fw/, runs its QAcademy Test suite
```

**The 60 minutes.** We type `readReg` and `writeReg`, which are the whole protocol in about sixty
lines and the one place byte order can go wrong, and then `read()`, because the poll, read and
separate pop is the L04 contract showing up on the other side of the wire. The remaining public
methods follow the same shape, and they, the scripted `driver::transport::Stub` and the blocking
helpers are left to the exercises. This is the heaviest C++ session, so it is the one where the
split matters most.

### After the Lecture
Work through the [exercises](./appendix/b_exercises.md): implement the `Uart` driver, build the
scripted stub, get the host suite green, then add the blocking helpers. The demo (`main.cpp`) is
provided, listed in full in [Exercise 3.2](./appendix/b_exercises.md#exercise-32---the-provided-demo),
so copy it in and run it to see them exercised end to end.

---

## Evaluation
* A `writeReg()` sends the four data bytes least significant first: what does the peripheral do with
  the value, and which test catches the byte-order mistake?
* Why is the driver tested against a scripted `driver::transport::Stub` rather than the real SPI at
  this stage, and what class of bug does that let you find first?
* The read path is poll `STATUS`, read `RX_DATA`, write `RX_POP`: what breaks if the driver skips
  the `RX_POP`, and what does the stub script assert to catch it?

---

## Next Lecture
The bottom layer becomes real: the AVR's own `SPCR` / `SPSR` / `SPDR`, `AvrSpi` implementing
`driver::transport::Interface`, and what a freestanding target removes. The driver, interface, and
register map all run unchanged.

---

