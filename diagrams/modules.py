"""The entity of every VHDL module in the peripheral.

Each figure is the module's outside and nothing more: the boundary, its ports, its generics.
That is what the "Designing `<module>.vhd`" appendices open with, and for the modules students
write it states the contract without giving away the architecture.

Ports are listed in **declaration order**, because the testbenches in `hw/` instantiate
positionally, so a transposed pair of same-type pins would analyze cleanly and fail only in
simulation. Two sources have to agree for every entity here, and both are checked:

* the port table in the module's appendix, and
* the `port map` in its `hw/<module>_tb.vhd`.

For a module that already exists, `hw/<module>.vhd` is the third and final word.
"""

from __future__ import annotations

from module_box import Entity, Port as P

# ----------------------------------------------------------------------------------------
# L01 - The peripheral top, and the blocks it is handed
# ----------------------------------------------------------------------------------------
# The only block that takes the raw asynchronous reset; everything inside takes reset_s2_n.
UART_TOP = Entity(
    "uart_top",
    [P("clock"), P("reset_n"), P("sclk"), P("mosi"), P("ss"), P("rx")],
    [P("miso"), P("tx")],
)
RESET_SYNC = Entity(
    "reset_sync",
    [P("clock"), P("reset_n")],
    [P("reset_s2_n")],
)
SPI_SLAVE = Entity(
    "spi_slave",
    [P("clock"), P("reset_s2_n"), P("sclk"), P("mosi"), P("ss"), P("tx_data", 8)],
    [P("miso"), P("rx_data", 8), P("rx_valid"), P("ss_active")],
)
SPI_REG_BRIDGE = Entity(
    "spi_reg_bridge",
    [
        P("clock"),
        P("reset_s2_n"),
        P("ss_active"),
        P("rx_data", 8),
        P("rx_valid"),
        P("reg_rdata", 32),
    ],
    [P("tx_data", 8), P("reg_addr", 4), P("reg_wdata", 32), P("reg_write")],
)

# ----------------------------------------------------------------------------------------
# L02 - The transmit datapath
# ----------------------------------------------------------------------------------------
# `div` is a scalar port rather than a vector, so it is labeled with its type. The range is
# spelled out because it is load-bearing: the lower bound is 1, not 0, so uart_top's guarded
# conversion of BAUD_DIV has to substitute a legal value rather than fall back on zero.
BAUD_GEN = Entity(
    "baud_gen",
    [
        P("clock"),
        P("reset_s2_n"),
        P("div", label="div (natural 1 to 65535)", bus=True),
    ],
    [P("tick")],
)
UART_TX = Entity(
    "uart_tx",
    [P("clock"), P("reset_s2_n"), P("baud_tick"), P("start"), P("data", 8)],
    [P("tx"), P("busy"), P("done")],
)

# ----------------------------------------------------------------------------------------
# L03 - Synchronization, the receive datapath, and the queue
# ----------------------------------------------------------------------------------------
SYNC = Entity(
    "sync",
    [P("clock"), P("reset_s2_n"), P("async_in", "COUNT-1:0")],
    [P("sync_out", "COUNT-1:0")],
    generics=[("COUNT", "natural 1 to 15")],
)
UART_RX = Entity(
    "uart_rx",
    [P("clock"), P("reset_s2_n"), P("baud_tick"), P("rx_s2")],
    [P("data_out", 8), P("valid"), P("frame_err")],
)
FIFO = Entity(
    "fifo",
    [P("clock"), P("reset_s2_n"), P("wdata", "WIDTH-1:0"), P("wr"), P("rd")],
    [P("rdata", "WIDTH-1:0"), P("empty"), P("full")],
    generics=[("WIDTH", "natural 1 to 64"), ("DEPTH", "natural 1 to 256")],
)

# ----------------------------------------------------------------------------------------
# L04 - The register bank
# ----------------------------------------------------------------------------------------
UART_REGS = Entity(
    "uart_regs",
    [
        P("clock"),
        P("reset_s2_n"),
        P("reg_addr", 4),
        P("reg_wdata", 32),
        P("reg_write"),
        P("tx_pop"),
        P("rx_byte", 8),
        P("rx_push"),
        P("tx_busy"),
        P("frame_err"),
    ],
    [
        P("reg_rdata", 32),
        P("baud_div", 16),
        P("tx_byte", 8),
        P("tx_empty"),
        P("rx_full"),
    ],
)

# Which lecture's appendix each module's figure belongs to. A module is drawn in the lecture
# that designs it; the three L01 entries are the provided blocks whose port tables the L01
# exercises hand out.
BY_LECTURE: dict[str, list[Entity]] = {
    "L01": [UART_TOP, RESET_SYNC, SPI_SLAVE, SPI_REG_BRIDGE],
    "L02": [BAUD_GEN, UART_TX],
    "L03": [SYNC, UART_RX, FIFO],
    "L04": [UART_REGS],
}
