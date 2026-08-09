# Appendix A

## Designing `uart_regs.vhd`
The datapath speaks in pulses and levels: a `valid` that is high for one clock, a `busy` that
rises and falls, a `tick`. Software speaks in **registers**: it writes a byte to a fixed address,
polls a status word, reads a byte back. The register bank is the translator between the two, and it
is the layer the whole [protocol spec](../../../protocol/uart_register_protocol.md) describes.

It owns two of the `fifo` you built in [L03](../../L03/appendix/c_fifo.md), the `CTRL`, `BAUD_DIV`
and `ERROR_FLAGS` registers, and it computes the read-only `STATUS` word. It is reached over a small
register bus that the provided SPI bridge drives; the bridge, not this module, is what turns SPI
transactions into `reg_write` strobes, so `uart_regs` can trust that a `reg_write` it sees is a
real, completed write.

---

### Interface

![Module `uart_regs`](./images/uart_regs.png)

| Port | Dir | Type | Meaning |
|---|---|---|---|
| `clock`, `reset_s2_n` | in | `std_logic` | Clock, and an active-low synchronized reset. |
| `reg_addr`  | in  | `std_logic_vector(3 downto 0)`  | Register index (`offset / 4`). |
| `reg_wdata` | in  | `std_logic_vector(31 downto 0)` | Write data. |
| `reg_write` | in  | `std_logic`                     | One-cycle commit strobe from the bridge. |
| `tx_pop`    | in  | `std_logic`                     | The transmitter has taken the front byte. |
| `rx_byte`   | in  | `std_logic_vector(7 downto 0)`  | A received byte, from the receiver. |
| `rx_push`   | in  | `std_logic`                     | Push `rx_byte` (the receiver's `valid`). |
| `tx_busy`   | in  | `std_logic`                     | The transmitter is mid-frame. |
| `frame_err` | in  | `std_logic`                     | The receiver saw a bad stop bit. |
| `reg_rdata` | out | `std_logic_vector(31 downto 0)` | Combinational read value for `reg_addr`. |
| `baud_div`  | out | `std_logic_vector(15 downto 0)` | `BAUD_DIV`, for `baud_gen`. |
| `tx_byte`   | out | `std_logic_vector(7 downto 0)`  | TX FIFO front, to the transmitter. |
| `tx_empty`  | out | `std_logic`                     | TX FIFO empty. |
| `rx_full`   | out | `std_logic`                     | RX FIFO full. |

The ports are declared all inputs first, then all outputs; `uart_regs_tb` binds them positionally,
so the order above is the contract. The testbench drives the register bus directly (standing in for
the bridge) and models the datapath side with plain signals, so the register semantics are tested
with no SPI in sight.

The register map itself (indices, offsets, bit positions) lives in the provided `uart_def` package,
so the bank and the testbench name registers and bits (`REG_STATUS`, `ST_TX_READY`, ...) instead of
magic numbers.

---

### Register semantics (the whole point of this module)
The map promises sticky, poll-able bits and FIFO-backed data. The datapath offers pulses and
levels. Bridging the two, bit by bit, is what the bank does. The three flag registers, from
[L01 Appendix A](../../L01/appendix/a_uart_def.md):

![Bit fields of `STATUS`, `CTRL` and `ERROR_FLAGS`](./images/reg_fields.png)

**`STATUS` is computed, never stored.** Bit 0 (TX ready) is `not tx_full`, bit 1 (RX valid) is
`not rx_empty`, bit 2 (Error) is the OR of the error flags, and bit 3 (TX idle) is `tx_empty and not
tx_busy`. Software polls these; nothing writes them.

**`TX_DATA` is a write-triggered action, not storage.** A `reg_write` to its index pushes
`reg_wdata(7 downto 0)` into the TX FIFO. It is an edge event, one write for one byte, and a
separate feeder in `uart_top` (L01 Appendix B) drains the FIFO into the transmitter.

**`RX_DATA` is a pure read; `RX_POP` is the advance.** Reading `RX_DATA` returns the FIFO's front
byte and changes nothing, so it obeys the same latch-once rule as `STATUS`, and discarding that byte
is a *separate* write to `RX_POP`. The split is deliberate. A read that also popped the FIFO would be
a read with a side effect, and it would need the same commit-on-completion, abort-safe handling as a
write: what should happen if the SPI transaction is aborted mid-read? Keeping the read pure and the
pop an explicit write sidesteps the question entirely, and it is the single most important idea in
this module.

**`ERROR_FLAGS` latches.** A `frame_err` pulse from the receiver sets the framing bit, and it stays
set until software writes `0` to clear it. `STATUS` bit 2 is just the OR of these flags.

**`CTRL` and `BAUD_DIV` are plain read/write registers.** `baud_div` is driven straight out to
`baud_gen`, so a `BAUD_DIV` write takes effect on the next baud tick the generator produces.

`CTRL` is different, and the difference matters: in this course it is **storage only, and gates
nothing**. Look at the port list above and you will not find a `ctrl` output, so there is no path
by which `CT_ENABLE`, the parity select, the stop-bit select or the two IRQ masks could reach the
datapath. They are stored, they read back, and nothing acts on them. Do **not** gate your TX push
or your receiver on `CT_ENABLE`: `uart_regs_tb` never writes `CTRL`, and neither does the system
testbench `uart_top_tb`, so a bank that waits to be enabled will simply never transmit and will
fail with a timeout that says nothing about the cause. The bits exist in `uart_def` because the
register map is the shared contract with the C++ side and with the protocol spec; wiring them to
something real is a natural extension, not part of the build here.

The bank never worries about aborted or partial transactions. The bridge only asserts `reg_write`
on a completed, non-aborted write (protocol spec, Part 3), so a strobe here is always a real
commit. That contract is exactly what lets `TX_DATA` and `RX_POP` be simple single-cycle actions.

---

### Behaviour
Very little of this module is clocked. It owns two `fifo` instances, three stored registers, and a
pile of decode; the register bus itself is combinational, and the only state that advances on an
edge is `ctrl_reg`, `baud_div_reg`, `err_flags`, and whatever the two FIFOs do internally.

Everything below is in the order you would type it: what to declare, what to instantiate, the
concurrent lines, then the one process.

The blocks and what connects them, first:

![Inside `uart_regs`](./images/regs_internals.png)

Read the two queues against each other and the asymmetry is the whole module. The TX FIFO takes its
data from the bus and its pop from the datapath; the RX FIFO takes its data from the datapath and
its pop from the bus. Everything else is the decode that turns one `reg_write` into one action, the
`flags` the `STATUS` word is assembled from, and the mux that answers reads.

Then the control flow. The left half of the module is one clocked decode, the right half is pure
combinational read-back, and they never touch:

```text
   on each rising edge, if reg_write = '1', decode reg_idx:
       REG_CTRL       : ctrl_reg(CT_TX_IRQ downto 0) <= reg_wdata(CT_TX_IRQ downto 0)
       REG_BAUD_DIV   : baud_div_reg <= reg_wdata(15 downto 0)
       REG_ERR_FLAGS  : err_flags    <= reg_wdata(2 downto 0)
       REG_TX_DATA    : nothing here - tx_push already pushed the FIFO
       REG_RX_POP     : nothing here - rx_pop already advanced the FIFO
       anything else  : ignored
   then, last in the process:
       if frame_err = '1' then err_flags(ER_FRAMING) <= '1'    -- beats a clear in the same cycle

   combinationally, every cycle, reg_rdata follows reg_idx:
       reg_rdata <= (others => '0')                             -- default, then override
       when REG_STATUS    => reg_rdata              <= status_reg
       when REG_CTRL      => reg_rdata              <= ctrl_reg
       when REG_BAUD_DIV  => reg_rdata(15 downto 0) <= baud_div_reg
       when REG_RX_DATA   => reg_rdata(7 downto 0)  <= rx_front  -- a read, never a pop
       when REG_ERR_FLAGS => reg_rdata(2 downto 0)  <= err_flags
       when others        => null                               -- TX_DATA, RX_POP, 7-15
```

A `TX_DATA` write is the one part of this that is easier to see in time than in structure. The
bridge holds the address and the word, raises `reg_write` for exactly one cycle, and the byte lands
on the edge inside it:

![A `TX_DATA` write, cycle by cycle](./images/bus_timing.png)

`tx_push` is combinational, so it is high for the same cycle as `reg_write`; the FIFO registers the
push on the edge at the end of that cycle, which is where `tx_empty` falls and `tx_byte` starts
showing the byte. That one-cycle strobe is the shape `uart_regs_tb`'s `bus_write` procedure drives,
and it is why `TX_DATA` needs no storage of its own.

**What to declare.** The port list already gives you every input and output, so the architecture
adds only what the ports cannot hold:
* `ctrl_reg[31:0]`: the control register (`CTRL`). Only bits 5-0 are ever written; bits 31-6 are
  reserved, so they stay at their reset value and read back as zero, exactly as `BAUD_DIV` and
  `ERROR_FLAGS` do with theirs.
* `baud_div_reg[15:0]`: the baud divider register (`BAUD_DIV`).
* `err_flags[2:0]`: the three error flags.
* `tx_push, rx_pop`: the two decoded write strobes.
* `tx_empty_s, tx_full_s, rx_empty_s, rx_full_s: std_logic`: the four FIFO flags.
* `rx_front[7:0]`: the RX FIFO's front byte, which the read mux needs.
* `status_reg[31:0]`: the assembled `STATUS` value.

**The two `fifo` instances.** Both are `generic map(8, 8)`, and both bind positionally:
* TX FIFO, in port order: `clock`, `reset_s2_n`, `reg_wdata(7 downto 0)`, `tx_push`, `tx_pop`,
  `tx_byte`, `tx_empty_s`, `tx_full_s`.
* RX FIFO, in port order: `clock`, `reset_s2_n`, `rx_byte`, `rx_push`, `rx_pop`, `rx_front`,
  `rx_empty_s`, `rx_full_s`.

Read those two lines against each other and the asymmetry is the whole module: the TX queue takes
its data from the bus and its pop from the datapath, and the RX queue takes its data from the
datapath and its pop from the bus. `tx_byte` binds straight to the output port because nothing in
here reads it; `rx_front` is internal because the read mux does.

**The concurrent assignments**, one line each, outside any process. Everything the read mux and the
clocked process below need is built here:
* `reg_idx` is `to_integer(unsigned(reg_addr))`, which needs `ieee.numeric_std`. Four address bits
  means 0 to 15, so the decode's `others` branch covers the reserved indices 7-15 for free.
* `tx_push` is `'1'` when `reg_write = '1'` and `reg_idx = REG_TX_DATA`, else `'0'`.
* `rx_pop` is `'1'` when `reg_write = '1'` and `reg_idx = REG_RX_POP`, else `'0'`.
* `tx_empty` follows `tx_empty_s`, and `rx_full` follows `rx_full_s`: the two flags that leave the
  module.
* `baud_div` follows `baud_div_reg`, straight out to the conversion in `uart_top`.
* `status_reg` is built one bit at a time, and every bit not named below is `'0'`:
    * `status_reg(ST_TX_READY)` is `not tx_full_s` - there is room to push.
    * `status_reg(ST_RX_VALID)` is `not rx_empty_s` - there is a byte to read.
    * `status_reg(ST_ERROR)` is `'1'` when `err_flags` is not all zeros - the OR of the three.
    * `status_reg(ST_TX_IDLE)` is `tx_empty_s and not tx_busy` - nothing queued *and* no frame in
      flight. TX ready is about room, TX idle is about quiet; software waits on the second before
      reconfiguring.
    * `status_reg(31 downto 4)` is `(others => '0')`, so the unused bits read back as the spec
      promises. Every bit needs exactly one driver, which is why this line exists at all.

**The read mux** is a combinational process: no clock, no register, one `case` on `reg_idx`. Assign
the zeros first and let each index override the bits it owns:

```vhdl
process(reg_idx, status_reg, ctrl_reg, baud_div_reg, rx_front, err_flags) is
begin
    reg_rdata <= (others => '0');            -- TX_DATA, RX_POP and 7-15 read zero
    case reg_idx is
        when REG_STATUS    => reg_rdata              <= status_reg;
        when REG_CTRL      => reg_rdata              <= ctrl_reg;
        when REG_BAUD_DIV  => reg_rdata(15 downto 0) <= baud_div_reg;
        when REG_RX_DATA   => reg_rdata(7 downto 0)  <= rx_front;   -- a read, never a pop
        when REG_ERR_FLAGS => reg_rdata(2 downto 0)  <= err_flags;
        when others        => null;
    end case;
end process;
```

Four things that shape holds down:

* **The default assignment comes first**, so every path through the process assigns `reg_rdata` and
  no latch is inferred. It also spares you five zero-extension expressions: assign the narrow
  register to the low bits and the leading zeros are already there.
* **`when others => null;` is honest here**, not lazy, precisely because of that default. Written
  without it, the same process would need `(others => '0')` spelled out in three more branches.
* **The reserved indices come free.** `reg_idx` is `natural range 0 to 15`, so `when others` covers
  7-15 as well as the two write-only registers, which is what Part 2 of the spec asks for.
* **The sensitivity list is spelled out.** VHDL-93 has no `process(all)` and this course analyzes
  with `--std=93`, so every signal the process reads has to be listed, or simulation and synthesis
  disagree about a mux that looked fine on the page. The provided `spi_reg_bridge` does exactly this
  in `hw/spi_reg_bridge.vhd`, and is worth reading as the pattern.

Because that path is combinational, `reg_rdata` follows `reg_addr` within the cycle. Nothing
registers it on the way out: the bridge latches the word once, at the start of its transaction, and
`uart_regs_tb` allows a settling delta (`SETTLE_NS`) before it samples.

**The clocked process** is `process(clock, reset_s2_n)`, asserted-asynchronously reset like every
other module here, and it is the only *clocked* process in the file - the read mux above is the
other one, and it has no clock at all:

* On reset (`reset_s2_n` is low):
    * `ctrl_reg` is cleared, so every `CTRL` bit reads back low.
    * `baud_div_reg` is cleared, so `BAUD_DIV` reads 0. A zero divider is not a legal input to
      `baud_gen`, which is why `uart_top` guards the conversion (L01 Appendix B); the driver is
      expected to write a real divider before using the line.
    * `err_flags` is cleared, so `STATUS` bit 2 reads low.
    * Nothing else. The FIFOs take `reset_s2_n` on their own ports and come out empty, which is what
      makes the first `STATUS` read after reset show TX ready and TX idle set with RX valid clear.
* On each rising edge of `clock`, while not in reset:
    * First, if `reg_write` is high, decode `reg_idx`:
        * **`REG_CTRL`**: `ctrl_reg(CT_TX_IRQ downto 0)` takes `reg_wdata(CT_TX_IRQ downto 0)`, so
          the six defined bits are stored and the reserved ones above them stay zero. Nothing else
          happens - no `ctrl` output exists, so the bits are stored, read back, and act on nothing.
        * **`REG_BAUD_DIV`**: `baud_div_reg` takes `reg_wdata(15 downto 0)`. The new divider reaches
          `baud_gen` combinationally, so it applies from the next tick the generator produces.
        * **`REG_ERR_FLAGS`**: `err_flags` takes `reg_wdata(2 downto 0)`, so the documented write of
          `0x0` clears all three latches.
        * **`REG_TX_DATA`** and **`REG_RX_POP`**: nothing happens *here*. Their whole effect is the
          concurrent strobe into a FIFO, which that FIFO registers on this same edge. Writing FIFO
          logic in this process as well is the most common way to get two bytes out of one write.
        * **`REG_STATUS`**, **`REG_RX_DATA`**, and indices 7-15: ignored. A write to a read-only or
          reserved register does nothing at all.
    * Then, *after* that decode, if `frame_err` is high, set `err_flags(ER_FRAMING)`.
    * Nothing else is clocked. No byte passes through a register on its way to `reg_rdata`, and no
      output is registered.

**Three things that catch people out.**

* **The order of the last two steps.** An `ERROR_FLAGS` clear and a fresh `frame_err` can land in
  the same cycle, and the last assignment in a process wins - the same rule `uart_rx` leans on for
  its tick counter. Putting the latch after the write decode means the new error survives the clear;
  the other order loses a real error to a write issued before it happened, and a dropped error flag
  is far worse than a stale one.
* **The FIFOs already guard themselves.** A `TX_DATA` write while the TX FIFO is full is dropped by
  the FIFO, and an `RX_POP` on an empty RX FIFO does nothing, both because L03 guarded them on `not
  full` and `not empty`. The bank adds no guards of its own; `STATUS` is what the driver is supposed
  to poll first.
* **Nothing is gated on `CT_ENABLE`.** As above: no testbench ever writes `CTRL`, so a bank that
  waits to be enabled never transmits.

Two things are deliberately absent. `ER_PARITY` and `ER_OVERRUN` have no producer in this build, so
they hold whatever a write last left in them, which is zero; `rx_full` is exported precisely so that
overrun detection can be added later without touching the map. And there is no TX feeder in here:
`tx_pop` is an *input*, driven by the feeder in `uart_top`, so this module never decides when the
transmitter takes a byte.

---

### What the testbench pins down
`uart_regs_tb` works entirely over the register bus. It checks that `BAUD_DIV` writes and reads back
and drives `baud_div`, and that `STATUS` after reset shows TX-ready and TX-idle set with RX-valid and
Error clear. On the transmit side, a `TX_DATA` write must appear at the FIFO front and clear TX-idle,
and a `tx_pop` must empty it again. On the receive side, an `rx_push` must set RX-valid, `RX_DATA`
must return the byte, a bare `RX_DATA` read must **not** pop, and an `RX_POP` write must clear
RX-valid. Finally, a `frame_err` must latch into `ERROR_FLAGS` and `STATUS`, and a write of `0`
must clear it. Two checks close the map off: a `CTRL` write of all ones must read back as
`0x0000003F`, proving the six defined bits are stored and the reserved ones above them are not, and
a write to reserved index 7 must be ignored with the read returning zero.

The read-does-not-pop check is the one that pins down the read/pop split; get it wrong and RX-valid
would clear on a plain read.

---

### Where it fits
`uart_regs` is the middle of `uart_top` (L01 Appendix B): the bridge on one side driving the register
bus, the datapath (`baud_gen`, `uart_tx`, `uart_rx`) on the other. Its two FIFOs are the buffers
that let software and the serial line run at their own speeds.

---

### What's ahead
[Appendix B](./b_exercises.md) is the exercises: build `uart_regs`, then instantiate the
bank into the `uart_top` skeleton from L01, the last block it was waiting for, and run the full
system testbench for the first time.

---

