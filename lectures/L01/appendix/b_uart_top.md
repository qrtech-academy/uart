# Appendix B

## Designing `uart_top.vhd`
`uart_top` is the peripheral: the datapath (`baud_gen`, `uart_tx`, `uart_rx`), the register bank
(`uart_regs`), and the provided SPI transport (`spi_slave`, `spi_reg_bridge`) that lets an off-chip
processor reach the registers. It is built **first**, top-down, before any of those blocks exist.
That is the point of starting here: the top defines every block's interface, so when `baud_gen`
arrives in L02 or `uart_regs` in L05, the ports each one must expose are already fixed by how
`uart_top` instantiates it.

What L01 produces is the top's *skeleton*: the entity, the provided `reset_sync`, the provided
transport, and the handful of signals those three need. It is wiring, almost entirely: the pieces of
real logic this file eventually holds, the TX feeder and one type conversion, are written later,
in the lectures that bring the signals they act on. The datapath and register blocks do not exist
yet; each is instantiated here as it is created across L02 through L05, and the system testbench
turns green once the last of them lands.

The signals follow the same rule. Rather than declaring names for modules that will not exist for
weeks, each lecture reads the entity of the block it is about to instantiate and declares exactly
the signals that block's ports imply. Two conventions keep it readable: a **`spi_` prefix** for
signals carrying SPI traffic between the two transport blocks, and an **`_s2` suffix** for anything
that has been through a two-flop synchronizer, which is why every submodule expects `reset_s2_n`.

This appendix is the reasoning behind the file. [Appendix C](./c_exercises.md) is where it is
actually typed, port by port and signal by signal.

---

### Interface

![Module `uart_top`](./images/uart_top.png)

| Port | Dir | Type | Meaning |
|---|---|---|---|
| `clock`   | in  | `std_logic` | 50 MHz system clock. |
| `reset_n` | in  | `std_logic` | Asynchronous reset, active low (a button or supervisor). |
| `sclk`, `mosi`, `ss` | in | `std_logic` | SPI from the processor. |
| `rx`      | in  | `std_logic` | The UART serial input. |
| `miso`    | out | `std_logic` | SPI to the processor. |
| `tx`      | out | `std_logic` | The UART serial output. |

The ports are declared all inputs first, then all outputs; `uart_top_tb` binds them positionally, so
the order above is the contract. Nothing in this course associates a port by name, which means a
transposed pair of same-type pins is invisible to the analyzer, and stays invisible until the system
testbench runs at the end of L05.

`uart_top` is the only block that takes `reset_n`, the raw asynchronous reset, from outside. The one
block inside it that also takes `reset_n` is `reset_sync`, because manufacturing a clean reset is its
whole job; every other block takes `reset_s2_n`, the synchronized version it produces.

---

### Skeleton behaviour (wiring, and one placeholder)
The transport comes first, because it is what makes a register bus exist at all. `spi_slave` and
`spi_reg_bridge` are given to you, testbench-verified; their wire protocol is Part 3 of the
[protocol spec](../../../protocol/uart_register_protocol.md) and their port lists are shown in
[Appendix C](./c_exercises.md). You instantiate them, you do not write them. `spi_slave` is the byte
engine: it shifts bytes in and out on `sclk` and reports each completed one. `spi_reg_bridge`
assembles those bytes into the five-byte register transactions the protocol defines, drives
`reg_addr`, `reg_wdata` and `reg_write`, and reads back whatever `reg_rdata` presents to it. The bank
that will answer on that bus arrives in L05; until then the bus exists with nothing behind it.

The **reset synchronizer** is provided, as `reset_sync`, and you instantiate it. `reset_n` comes
from off-chip, so it can be released at any instant relative to `clock`. A release landing near a
clock edge could let different flip flops leave reset on different cycles, and a design that starts
half-reset can sit in a state its own logic never expects. `reset_sync` asserts asynchronously, so
the moment `reset_n` goes low everything resets with no clock needed, and releases synchronously,
two flip flops later, so the release is lined up with the clock. Its two internal flops stay inside
it, so the only signal it adds to your top is `reset_s2_n`.

That output then feeds every submodule, and the blocks you write in L02 through L05 all take it the
same way the provided ones do: `reset_s2_n` goes in the process's sensitivity list, so the assertion
still needs no clock edge, while the *release* is already lined up because `reset_sync` lined it up.
That is the house style throughout `hw/`, and it is what makes an asynchronous assertion safe in the
first place: the dangerous edge, the release, was dealt with once, here.

Note this job is not `sync`'s (L03), even though that module is also two flops in series. `sync`
takes `reset_s2_n` as an *input*, so it consumes the very signal `reset_sync` produces, and a block
that needs a clean reset cannot be the block that manufactures one.

The **TX feeder** is written in L05, once both signals it needs exist. `uart_tx` (L02) sends a byte
when its `start` is pulsed, and the TX FIFO inside `uart_regs` (L05) holds the bytes waiting to go.
The feeder is what connects them: `tx_load` is FIFO-not-empty AND transmitter-not-busy, and `tx_pop`
is that same signal, so the transmitter latches the front byte and the FIFO advances in the same
cycle. The instant the transmitter goes busy `tx_load` drops, so exactly one byte moves per idle
transmitter, never two. The RX side needs no feeder at all: the receiver's `valid` and `data_out`
become `uart_regs`' `rx_push` and `rx_byte`, and the bank pushes its own FIFO.

The other piece is a **type conversion**, written in L02 alongside `baud_gen`. `baud_gen` takes its
divider as a `natural range 1 to 65535`, but `BAUD_DIV` leaves the register bank as a
`std_logic_vector(15 downto 0)`, so `uart_top` converts it. That conversion is guarded, because
until `uart_regs` exists in L05 nothing drives the vector, and `to_integer` on an all-`'U'` value
warns and substitutes a zero of its own choosing, which is a value that port's range does not
accept. Picking a legal value yourself costs one conditional expression, and this is the only place
in `uart_top` where a `std_logic_vector` becomes an integer.

The one thing L01 does write is a **placeholder**: `reg_rdata` tied to zeros, so the bridge reads a
defined value rather than `'U'` while the register bank is missing. It is deleted in L05 when
`uart_regs` starts driving that vector for real.

---

### What the testbench pins down
`uart_top_tb` is the system testbench, and it does not run until the last block lands in L05. It
drives the peripheral entirely over SPI, as the processor would, and loops `tx` back into `rx`. A
single byte written over SPI is therefore transmitted, received through the loopback, pushed into the
RX FIFO, and read back over SPI: an end-to-end check that the reset synchronizer, the transport, the
register bank, the FIFOs, the feeder and both datapath halves all agree. It also writes `BAUD_DIV` and
reads it back, and checks `STATUS`, so the register plumbing is exercised alongside the datapath.

Its one line of instantiation is also why the entity looks the way it does. The bench binds
`port map(clock, reset_n, sclk, mosi, ss, rx, miso, tx)`, and that order, not the diagram above it,
is what the port table records.

---

### Where it fits
`uart_top` faces two directions. Outward, its eight pins are the FPGA boundary: `sclk`, `mosi`, `ss`
and `miso` reach the ATmega328P on the other side of the wire, and the driver built in L06 through
L09 talks to exactly these ports; `rx` and `tx` are the serial line itself. In L09 a board wrapper
sits above it and maps those pins onto DE0-CV package pins, which is the only thing that wrapper
does.

Inward, it is the one file revisited in every VHDL lecture, and each visit adds a block, the signals
that block's entity implies, and any glue those signals now make possible. L01 leaves it with the
entity, `reset_sync`, the transport and a register bus nothing answers. L02 adds `baud_gen` and
`uart_tx`, and with them the `BAUD_DIV` conversion, so the top can transmit. L04 adds `sync` on the
`rx` pin, producing `rx_s2`, and `uart_rx` behind it, so the receiver never sees the raw
asynchronous input. L05 adds `uart_regs`, which owns both FIFOs, and the TX feeder that connects it
to the transmitter; with every block present the system testbench elaborates for the first time. The
rule that keeps it compiling throughout is that you only ever instantiate an entity after you have
created it.

---

### What's ahead
[Appendix C](./c_exercises.md) is the exercises, and for `uart_top` it is also the build sheet:
everything needed to type the file, from the entity down to the last internal signal, is there. In
L02 you build the first two datapath blocks, `baud_gen` and `uart_tx`, and instantiate them here.

---

