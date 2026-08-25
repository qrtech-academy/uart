# L05 - The Register Bank

## Agenda
This lecture is about the distance between port semantics and register semantics. The TX and RX cores
speak in pulses and levels, while the [register map](../../protocol/uart_register_protocol.md)
promises sticky, poll-able bits and FIFO-backed data; bridging the two is the whole job. We cover:

* **The two FIFOs from L04**, one per direction, instantiated by the bank rather than by the top.
* **The register bank** (`uart_regs.vhd`) around them: `STATUS` computed straight from the FIFO
  flags, the `ERROR_FLAGS` latches, `CTRL` and `BAUD_DIV` as plain storage, the write-triggered
  `TX_DATA` push, and the read-then-pop RX path in which `RX_DATA` is a pure read and `RX_POP` is
  the separate, abort-safe write that advances the FIFO.
* **Completing `uart_top`**: instantiating `uart_regs`, which owns both FIFOs, into the skeleton
  from L01, the last block it was waiting for, so the full system testbench runs for the first time.

---

## Objectives
After this lecture, participants should be able to:

* **Explain why a single-cycle error pulse cannot be polled**, and implement pulse-to-level latching
  with a defined set and clear pair for each `ERROR_FLAGS` bit, while deriving every `STATUS` bit
  combinationally from the FIFO flags instead.
* **Explain why popping a FIFO on read would need write-like commit-and-abort discipline**, and why
  splitting the pure read (`RX_DATA`) from the explicit pop (`RX_POP`) avoids it.
* **Instantiate the register bank into `uart_top` positionally**, completing the peripheral so that
  it passes the system testbench.

---

## Prerequisites
This lecture completes what L01 started, so you need the `uart_top` skeleton and the `uart_def`
package from it, and the datapath blocks from L02 and L03, `baud_gen`, `uart_tx` and `uart_rx`,
along with the pulses and levels they expose, wired into the top across L02 and L04. You also need
the `fifo` from L04, which this bank instantiates twice. Read the full [protocol
spec](../../protocol/uart_register_protocol.md) beforehand, especially **Register Semantics** and
**Part 3 - The SPI Transport**, which you instantiate but do not write.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_uart_regs.md) for `uart_regs`; that is the specification you build it
from. The two FIFOs it owns were built in [L04](../L04/appendix/a_fifo.md) and are already in `hw/`.
Revisit [L01 Appendix B](../L01/appendix/b_uart_top.md) for the top you now complete. Then read the
provided testbench [`uart_regs_tb.vhd`](../../hw/uart_regs_tb.vhd), along with the system testbench
[`uart_top_tb.vhd`](../../hw/uart_top_tb.vhd), which plays SPI transactions through the provided
transport and watches a byte cross the whole peripheral.

### During the Lecture
We live-code the heart of `uart_regs.vhd`, then instantiate `uart_regs` into `uart_top`. With every
block present, the system testbench elaborates and runs:

```bash
make build-vhdl        # from the repository root: runs every testbench whose modules exist
```

**The 60 minutes.** We type the two ideas and run the payoff: `STATUS` computed straight from the
FIFO flags rather than stored, and the `RX_DATA` / `RX_POP` split with the reasoning behind it. Then
we instantiate `uart_regs` into `uart_top` and watch the system testbench run for the first time,
which is the moment the FPGA half becomes a thing that works. The remaining register decode is seven
near-identical cases and the `ERROR_FLAGS` latch is one more; both are left to the exercises.

### After the Lecture
Work through the [exercises](./appendix/b_exercises.md): build `uart_regs`, then instantiate the
bank into the `uart_top` skeleton from L01, delete the `reg_rdata` placeholder you left there (L01
Appendix C, Exercise 2d), and run the full system testbench.

---

## Evaluation
* Why can `STATUS` bit 1 (RX valid) not simply be wired to the receiver's "byte ready" pulse?
* A `TX_DATA` write arrives while `STATUS` bit 0 (TX ready) is clear: what happens, and why is
  dropping the byte the right choice here?
* `SS` rises after the third byte of an `RX_POP` write: what must the peripheral do, and which part
  of the transport contract guarantees it?
* If reading `RX_DATA` returns a byte but never advances the FIFO, what did the driver forget, and
  what would go wrong if `RX_DATA` popped on its own?

---

## Next Lecture
The FPGA half is done. The driver stack begins, on the host, with no hardware: the
`driver::uart::Interface` and its `driver::transport::Interface` seam, then a first
`driver::uart::Stub` written against that interface.

---

