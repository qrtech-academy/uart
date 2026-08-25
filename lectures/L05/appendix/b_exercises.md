# Appendix B

## Exercises
Exercise 1 reinforces [Appendix A](./a_uart_regs.md), and Exercise 2 completes `uart_top` from
[L01 Appendix B](../../L01/appendix/b_uart_top.md). The `fifo` the register bank owns was built in
[L04](../../L04/appendix/a_fifo.md), so it is already in `hw/` and ready to instantiate. Build each
module from its appendix and check it with the provided testbench, run from `hw/` (see
[`hw/README.md`](../../../hw/README.md)).

---

## Exercise 1 - `uart_regs`
**a)** Write your own `uart_regs.vhd` from [Appendix A](./a_uart_regs.md)'s specification and run its
testbench:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd fifo.vhd uart_regs.vhd uart_regs_tb.vhd
ghdl -e --std=93 uart_regs_tb
ghdl -r --std=93 uart_regs_tb --assert-level=error
```

`uart_def.vhd` (the register map) and `fifo.vhd` come first because `uart_regs` reads the package
and instantiates two FIFOs.

**b)** Make `RX_DATA` pop the FIFO on read (advance `tail` whenever that index is read). Re-run. The
"a bare `RX_DATA` read must not pop" check fails; explain, in terms of the SPI transport's abort
rule, why a read with a side effect is a genuinely harder thing to get right than the pure read
plus separate `RX_POP`.

**c)** `STATUS` is computed, not stored. Name the four things each of its bits is derived from, and
say why none of them can simply be a stored register that the datapath writes.

**d)** The bank acts on every `reg_write` it sees as a real commit. What does it rely on the
provided SPI bridge to guarantee for that to be safe, and what would break if a half-finished
(aborted) transaction could reach it as a `reg_write`?

---

## Exercise 2 - `uart_top`
**a)** You built the `uart_top` skeleton in L01 and added `baud_gen`, `uart_tx`, `sync` and `uart_rx`
across L02, L03 and L04, declaring each block's signals as you went. Now do it once more for
`uart_regs`, the last block the top was waiting for. Three signals are new here:

| Signal | Type | Driven by | Read by |
|---|---|---|---|
| `tx_empty` | `std_logic` | `uart_regs` | the feeder below |
| `rx_full`  | `std_logic` | `uart_regs` | nothing, in this build |
| `tx_pop`   | `std_logic` | the feeder below | `uart_regs` |

Every other port below is a signal you already declared in L01, L02, L03 or L04 - which is the point
of having declared them where they were needed.

![Module `uart_regs`](./images/uart_regs.png)

| # | `uart_regs` port | Dir | Type | Connect to |
|---|---|---|---|---|
| 1  | `clock`      | in  | `std_logic`                     | `clock` |
| 2  | `reset_s2_n` | in  | `std_logic`                     | `reset_s2_n` |
| 3  | `reg_addr`   | in  | `std_logic_vector(3 downto 0)`  | `reg_addr` (L01) |
| 4  | `reg_wdata`  | in  | `std_logic_vector(31 downto 0)` | `reg_wdata` (L01) |
| 5  | `reg_write`  | in  | `std_logic`                     | `reg_write` (L01) |
| 6  | `tx_pop`     | in  | `std_logic`                     | `tx_pop` |
| 7  | `rx_byte`    | in  | `std_logic_vector(7 downto 0)`  | `rx_byte` (L04) |
| 8  | `rx_push`    | in  | `std_logic`                     | `rx_push` (L04) |
| 9  | `tx_busy`    | in  | `std_logic`                     | `tx_busy` (L02) |
| 10 | `frame_err`  | in  | `std_logic`                     | `frame_err` (L04) |
| 11 | `reg_rdata`  | out | `std_logic_vector(31 downto 0)` | `reg_rdata` (L01) |
| 12 | `baud_div`   | out | `std_logic_vector(15 downto 0)` | `baud_div` (L02) |
| 13 | `tx_byte`    | out | `std_logic_vector(7 downto 0)`  | `tx_byte` (L02) |
| 14 | `tx_empty`   | out | `std_logic`                     | `tx_empty` |
| 15 | `rx_full`    | out | `std_logic`                     | `rx_full` |

```vhdl
-- The register bank: the bridge's bus on one side, the datapath on the other. This closes
-- every loop in the design - the bus now has something answering on it, the transmitter has
-- a byte source, and the receiver has somewhere to put what it recovers.
uart_regs: entity work.uart_regs
    port map(clock, reset_s2_n, reg_addr, reg_wdata, reg_write, tx_pop, rx_byte, rx_push,
             tx_busy, frame_err, reg_rdata, baud_div, tx_byte, tx_empty, rx_full);
```

Delete the `reg_rdata <= (others => '0');` placeholder from L01 in the same edit: the bank drives
that vector now, and leaving the placeholder in gives it two drivers.

With `tx_empty` finally driven, the **TX feeder** can be written, the one piece of real logic the top
has been waiting to hold. It is two concurrent statements:

```vhdl
-- The TX feeder: load the transmitter whenever a byte is queued and the line is free, and pop
-- the FIFO on that same edge, so exactly one byte moves per idle transmitter. The instant the
-- transmitter goes busy, tx_load drops - which is what stops a second byte following it.
tx_load <= (not tx_empty) and (not tx_busy);
tx_pop  <= tx_load;
```

Note why this could not have been written earlier: `tx_empty` comes from the register bank and
`tx_busy` from the transmitter, so the feeder needs a block from L02 and a block from L05 to exist
at the same time. That is the general shape of this design, and the reason signals are declared
where they are needed rather than all at once in L01.

The receive side needs no equivalent: `uart_rx`'s `valid` went straight to `rx_push` in L04, so the
receiver pushes its own byte into the RX FIFO.

Then run the system testbench:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd reset_sync.vhd baud_gen.vhd sync.vhd fifo.vhd uart_tx.vhd \
     uart_rx.vhd uart_regs.vhd spi_slave.vhd spi_reg_bridge.vhd uart_top.vhd uart_top_tb.vhd
ghdl -e --std=93 uart_top_tb
ghdl -r --std=93 uart_top_tb --assert-level=error
```

Everything the design contains appears on that line, in dependency order, including `fifo`, which
`uart_top` never instantiates itself: `uart_regs` owns both of them. With the last block in place,
the system testbench elaborates the whole peripheral for the first time.

If `uart_top_tb` fails on the `BAUD_DIV` read-back with every `1` bit missing from the value you
wrote, and the run is littered with `NUMERIC_STD.TO_INTEGER: metavalue detected` warnings, the L01
placeholder is still there: each `'1'` the bank drives is resolving against its `'0'` to `'X'`.

**b)** The provided `reset_sync` asserts asynchronously but releases synchronously. Explain what
could go wrong if it released `reset_s2_n` asynchronously too (the moment `reset_n` rises), and why
asserting asynchronously is nonetheless the right choice.

**c)** Why can `reset_sync` not just be a `sync` instance, given that both are two flip flops in
series? Name the port that settles it, and describe the circular dependency you would create by
trying.

**d)** Study the TX feeder you wrote in a): `tx_load <= (not tx_empty) and (not tx_busy)`. Argue
that it loads **exactly one** byte each time the transmitter goes idle with the FIFO non-empty,
never zero and never two. What holds `tx_load` low for the rest of the frame?

**e)** The system testbench loops `tx` back to `rx`. Trace a single byte: SPI write of `TX_DATA`,
through the FIFO and transmitter, out `tx`, back in `rx`, through the receiver into the RX FIFO, and
out again on an SPI read of `RX_DATA`. Name the block that acts at each step.

---

