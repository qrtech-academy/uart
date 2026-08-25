# L04 - The FIFO & the Receive Path

## Agenda
One module and one wiring job, both of which L05 depends on. We cover:
* **A small synchronous FIFO** (`fifo.vhd`): a ring buffer with a head, a tail and a count, written
  once as a generic module because the register bank in L05 needs two of them, one per direction.
* **The look-then-advance read**: `rdata` shows the front entry continuously and `rd` is what
  *discards* it. That split is not a stylistic choice - it is exactly what lets L05 keep `RX_DATA` a
  pure read with a separate `RX_POP`, and it is the first place in the course where a register's
  semantics reach down into a datapath block's ports.
* **The corner cases that a count gets wrong**: a write to a full FIFO and a read from an empty one,
  both dropped rather than allowed to cross the pointers, and a `wr` and `rd` on the same edge,
  where a count adjusted in two independent branches quietly loses an entry.
* **The receive path in `uart_top`**: `sync` on the `rx` pin producing `rx_s2`, then L03's `uart_rx`
  behind it, so the pin crosses into the clock domain once, in the module that owns the pin.
* **Where overrun lives**: the receiver reports a framing error but can never report an overrun,
  because it does not know whether anyone has read the previous byte. The RX FIFO's `full` flag is
  what makes it visible, and the register bank in L05 is what reports it.

---

## Objectives
After this lecture, participants should be able to:
* **Build a synchronous FIFO** with a look-then-advance read, and explain why that split is what
  lets L05 keep `RX_DATA` a pure read.
* **Say what `full` and `empty` guard**, and what a write to a full FIFO or a read from an empty one
  must do instead of wrapping the pointers past each other.
* **Instantiate the receive path into `uart_top`** in the right order, with the synchronizer on the
  pin and the receiver behind it, and explain why binding `rx` straight to `uart_rx` would analyze
  cleanly and still be wrong.
* **Explain what an overrun is**, why the receiver cannot detect one on its own, and which block
  has the one piece of information that makes it detectable.

---

## Prerequisites
This lecture needs L03's `sync` and `uart_rx`, which Exercise 2 instantiates, and the `uart_top`
skeleton from L01 that they go into, with `baud_gen` and `uart_tx` already in it from L02. Nothing
new is assumed from the foundational courses: the FIFO is an ordinary clocked design with an array,
two pointers and a count.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_fifo.md) for `fifo`; that is the specification you build the module
from. Then read the provided testbench, [`fifo_tb.vhd`](../../hw/fifo_tb.vhd), which uses a depth-4
instance: it checks `empty` after reset and `full` after four pushes, drops a fifth push rather than
overwriting, drains the four bytes in the order they went in, and finally raises `wr` and `rd` on
the same edge with two entries queued - one in and one out, so the depth must not move.

### During the Lecture
We live-code `fifo.vhd` against its testbench:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd fifo.vhd fifo_tb.vhd
ghdl -e --std=93 fifo_tb && ghdl -r --std=93 fifo_tb --assert-level=error
```

Then we return to `uart_top` and add the receive path, which is two instantiations rather than one:
`sync` on the `rx` pin, then `uart_rx` reading `rx_s2` rather than `rx`. The top analyzes with only
`uart_regs` still missing, and the system testbench stays skipped until L05 supplies it. The FIFO is
not instantiated here at all - it belongs to the register bank that owns it.

**The 60 minutes.** We type the FIFO's clocked process and its flags, spending the time on the two
places it goes wrong: the guards that keep the pointers from crossing, and the count on a
simultaneous push and pop. Then the two instantiations in `uart_top`, which are short and are the
point of the lecture as much as the module is - the pin crosses once, in the module that owns it.
The remaining FIFO polish and the closing overrun discussion are the exercises.

### After the Lecture
Work through the [exercises](./appendix/b_exercises.md): build `fifo` from Appendix A and run its
testbench, add `sync` and `uart_rx` to `uart_top`, then reason about why overrun detection belongs
to the register bank rather than the receiver.

---

## Evaluation
* `rdata` shows the front entry with no `rd` at all. What would break in L05's `RX_DATA` / `RX_POP`
  split if the FIFO instead popped on every read?
* A write arrives while the FIFO is full. What must happen to `wdata`, to `head` and to `count`, and
  what tells the caller it happened?
* What is an overrun, why can the receiver not detect one on its own, and which block would have to
  do it instead?

---

## Next Lecture
Ports become registers: sticky `STATUS` bits, a write-triggered TX push, the read-then-pop RX path
over two of the FIFOs you just built, and completing `uart_top` behind the provided SPI transport,
so the system testbench finally runs.

---
