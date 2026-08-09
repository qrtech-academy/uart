# The Peripheral
This is where the UART peripheral gets built. Every VHDL file the course produces lives here, in
one flat directory: the modules you write, alongside the instructor-provided testbenches that
check them, the provided SPI transport, and the provided register-map package. Nothing is copied
between lecture directories.

The gating, the three-step GHDL flow, and the positional-binding convention are deliberate; each
is explained below.

---

## What goes here, and when

| File | Written in | Provided |
|---|---|:---:|
| `uart_def.vhd` | | yes (package) |
| `reset_sync.vhd` | | yes |
| `uart_top.vhd` | L01 | |
| `uart_top_tb.vhd` | | yes |
| `baud_gen.vhd` | L02 | |
| `baud_gen_tb.vhd` | | yes |
| `uart_tx.vhd` | L02 | |
| `uart_tx_tb.vhd` | | yes |
| `sync.vhd` | L03 | |
| `sync_tb.vhd` | | yes |
| `uart_rx.vhd` | L03 | |
| `uart_rx_tb.vhd` | | yes |
| `fifo.vhd` | L03 | |
| `fifo_tb.vhd` | | yes |
| `uart_regs.vhd` | L04 | |
| `uart_regs_tb.vhd` | | yes |
| `spi_slave.vhd` | | yes (transport) |
| `spi_slave_tb.vhd` | | yes |
| `spi_reg_bridge.vhd` | | yes (transport) |
| `spi_reg_bridge_tb.vhd` | | yes |

The directory starts out holding the nine testbenches, the provided SPI transport (`spi_slave.vhd`,
`spi_reg_bridge.vhd`), the provided reset synchronizer (`reset_sync.vhd`), and the provided
register-map package (`uart_def.vhd`). Each lecture then adds the module(s) it live-codes: L01 the
peripheral top (`uart_top`), L02 the baud generator and transmitter, L03 the synchronizer, the
receiver and the FIFO, L04 the register bank. `uart_top` is built top-down in L01 and gains one
datapath block per lecture; its system testbench stays skipped until the last block lands in L04.

The provided transport is a **black box** in this course: you instantiate `spi_slave` and
`spi_reg_bridge` in `uart_top`, but you do not write or modify them. The wire protocol they
implement is [Part 3 of the protocol spec](../protocol/uart_register_protocol.md); their port lists,
which is what you need in order to instantiate them, are tabulated in
[L01 Appendix C](../lectures/L01/appendix/c_exercises.md). Each has its own testbench
(`spi_slave_tb`, `spi_reg_bridge_tb`) if you want to see them exercised.

The DE0-CV board wrapper (`uart_board.vhd`, the Quartus top level with the pin assignments) is
deliberately **not** here: it is board I/O rather than peripheral logic, is never exercised by
these testbenches, and belongs with the Quartus project. That project - the wrapper and the pin
assignment file - is handed out at the start of L07, which is where the design is first synthesized
and programmed; L08 only edits it, to jumper pins for the bring-up ladder.

---

## Running a testbench
From this directory, the three GHDL steps, dependencies first. For example, the transmitter:

```bash
ghdl -a --std=93 uart_tx.vhd uart_tx_tb.vhd
ghdl -e --std=93 uart_tx_tb
ghdl -r --std=93 uart_tx_tb --assert-level=error
```

`uart_top_tb` is the system testbench: it drives the peripheral through the provided SPI
transport, writes a byte via the register map, and reads it back through `RX_DATA`. The bench ties
`rx` to `tx` in loopback, so the byte the peripheral transmits is the byte it receives. It needs
every module analyzed first:

```bash
ghdl -a --std=93 uart_def.vhd reset_sync.vhd baud_gen.vhd sync.vhd fifo.vhd uart_tx.vhd \
     uart_rx.vhd uart_regs.vhd spi_slave.vhd spi_reg_bridge.vhd uart_top.vhd uart_top_tb.vhd
ghdl -e --std=93 uart_top_tb
ghdl -r --std=93 uart_top_tb --assert-level=error
```

Or run everything that's ready, from the repository root:

```bash
make build-vhdl
```

which skips (rather than fails) any testbench whose modules don't exist yet. `--assert-level=error`
makes a failed check stop the simulation with a non-zero exit code rather than printing and
running on to a misleading "pass".

Running `uart_regs_tb` or `uart_top_tb` by hand also prints one `NUMERIC_STD.TO_INTEGER: metavalue
detected` note at time 0. It is harmless - it comes from evaluating `to_integer(unsigned(reg_addr))`
in the delta before any driver has resolved - and `make build-vhdl` suppresses it with
`--ieee-asserts=disable-at-0`, which silences IEEE library assertions at time 0 only and leaves
every assertion in these testbenches firing normally. Add the same flag to a manual `ghdl -r` if the
note gets in your way.

---

## Port order
Every testbench binds to the module it drives **positionally**, and so does every instantiation
inside `uart_top`. Nothing in this course associates a port by name.

So the contract is the **order and the types** of the ports, exactly as each appendix's Interface
table lists them, top to bottom. The port *names* are yours: rename a signal and everything still
binds, as long as it keeps its position and type. The appendices keep their port names anyway, so
the lecture text and your code talk about the same signals.

---

