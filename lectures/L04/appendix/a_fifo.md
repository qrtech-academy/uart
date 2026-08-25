# Appendix A

## Designing `fifo.vhd`
The datapath produces and consumes bytes at different rates:
* Software writes a byte to send whenever it likes.
* The transmitter sends one every ten bit-times.
* The receiver delivers a byte every frame.
* Software reads it whenever it gets round to it.

A **FIFO** (first in, first out queue) absorbs that mismatch: bytes go in one end and come out the
other in the same order, and each side can run without waiting for the other, up to the depth of
the queue.

The register bank (L05 Appendix A) needs two of these, one for each direction, so `fifo` is written
once as a generic module and instantiated twice.

---

### Interface

![Module `fifo`](./images/fifo.png)

| Port / generic | Dir | Type | Meaning |
|---|---|---|---|
| `WIDTH` | generic | `natural range 1 to 64 := 8`  | Bits per entry. |
| `DEPTH` | generic | `natural range 1 to 256 := 8` | Number of entries. |
| `clock`      | in  | `std_logic`                     | 50 MHz system clock. |
| `reset_s2_n` | in  | `std_logic`                     | Active-low synchronized reset. |
| `wdata` | in  | `std_logic_vector(WIDTH-1 downto 0)` | The entry to push. |
| `wr`    | in  | `std_logic`                          | '1' to push `wdata` this cycle. |
| `rd`    | in  | `std_logic`                          | '1' to pop the front entry this cycle. |
| `rdata` | out | `std_logic_vector(WIDTH-1 downto 0)` | The entry at the front (combinational). |
| `empty` | out | `std_logic`                          | '1' if the FIFO is empty. |
| `full`  | out | `std_logic`                          | '1' if the FIFO is full.  |

`fifo_tb` binds the ports positionally and drives the generic map too, instantiating a depth-4
FIFO. `rdata` shows the front entry continuously, without a `rd`; `rd` is what *discards* it and
moves to the next. That split (look, then advance) is exactly what the RX path in L05 needs.

---

### Behaviour
A ring buffer: an array of `DEPTH` entries, a write pointer (`head`), a read pointer (`tail`), and a
count. Each pointer wraps around from `DEPTH-1` back to 0.

On reset (`reset_s2_n` low), `head`, `tail` and `count` all go to 0, so the FIFO comes out of reset
empty and not full; as everywhere else in this peripheral the reset is asserted asynchronously and
tested ahead of `rising_edge(clock)`. The entries themselves need no clearing, since with
`count = 0` nothing in the array is reachable and the first write lands on entry 0 anyway. What does
matter is that the two pointers start *equal*, not merely at some known value: `empty` and `full`
are read off `count`, so a `head` and `tail` that disagreed out of reset would keep the count
honest while handing back a stale entry instead of the byte just pushed. `rdata` does show entry 0
while the FIFO is empty, whatever that entry happens to hold, which is one more reason the caller
watches `empty` rather than trusting `rdata`.

On each rising edge, while not in reset, a **write** happens only if `wr = '1'` and the FIFO is not
full, storing `wdata` at `head` and advancing `head`; a **read** happens only if `rd = '1'` and the
FIFO is not empty, advancing `tail`. The count follows from the pair: it rises by one on a
write without a read, falls by one on a read without a write, and is unchanged when both or neither
happen.

`full` is `count = DEPTH`, `empty` is `count = 0`, and `rdata` is combinationally the entry at
`tail`. Guarding writes on `not full` and reads on `not empty` means the pointers can never cross;
a write to a full FIFO and a read from an empty one are simply dropped, which is why the caller must
watch the flags.

---

### What the testbench pins down
`fifo_tb` uses a depth-4 instance. It checks `empty` after reset and `full` after four pushes, then
pushes a fifth entry while full and confirms it is dropped rather than stored over an existing one,
and finally drains the FIFO and checks the four bytes come back in the order they went in, leaving it
`empty` again. A last case raises `wr` and `rd` on the same edge with two entries queued: one entry
in and one out, so the depth must not move, and the byte pushed alongside the pop must still be
there after the next one. That is the case where a count adjusted in two independent branches
quietly loses an entry.

That is the whole contract: order preserved, and the flags honest at both ends.

---

### Where it fits
The register bank (L05 Appendix A) instantiates two `fifo`s, both `WIDTH = 8, DEPTH = 8`: a TX FIFO
that a `TX_DATA` register write pushes and the transmitter drains, and an RX FIFO that the receiver
pushes and an `RX_DATA` read plus `RX_POP` write drains. The FIFO's `full`/`empty` flags become the
`STATUS` register's TX-ready and RX-valid bits.

---

### What's ahead
[Appendix B](./b_exercises.md) is the exercises: build `fifo` and run its testbench, put the L03
receive path into `uart_top`, and work out why overrun is not the receiver's question to answer.
Then [L05 Appendix A](../../L05/appendix/a_uart_regs.md) builds `uart_regs`, the register bank,
which wraps two of these FIFOs and the datapath in the register map that software drives.

---

