"""One register-bus write, cycle by cycle: what `TX_DATA` actually does.

Everything else about the bank is structural, and a block diagram or a port table says it
better. This is the part that is temporal: the bridge holds an address and a word, raises
`reg_write` for exactly one cycle, and the byte lands in the TX FIFO on the edge inside that
cycle - after which `tx_empty` falls and the front byte appears on `tx_byte`.

The shape here is the one `uart_regs_tb`'s `bus_write` procedure drives.
"""

from __future__ import annotations

from schemdraw.logic.timing import TimingDiagram

import style

# WaveJSON, one character per clock cycle. '=' opens a data block, '.' holds the previous
# value. Cycle 1 is the write; the edge into cycle 2 is where the FIFO registers it.
WAVES = {
    "signal": [
        {"name": "clock", "wave": "p....."},
        {"name": "reg_addr", "wave": "x=.x..", "data": ["TX_DATA"]},
        {"name": "reg_wdata", "wave": "x=.x..", "data": ["0x5A"]},
        {"name": "reg_write", "wave": "010..."},
        {"name": "tx_push", "wave": "010..."},
        {"name": "tx_empty", "wave": "1.0..."},
        {"name": "tx_byte", "wave": "x.=...", "data": ["0x5A"]},
    ]
}

YHEIGHT = 0.5
YGAP = 0.35
RISETIME = 0.12


def _draw(d, ax) -> None:
    d.add(
        TimingDiagram(
            WAVES,
            yheight=YHEIGHT,
            ygap=YGAP,
            risetime=RISETIME,
            fontsize=style.FONT_SIZE,
            datafontsize=style.FONT_SIZE,
            namecolor=style.LINE_COLOR,
            datacolor=style.LINE_COLOR,
            tickcolor=style.LINE_COLOR,
            gridcolor="#c8c8c8",
            color=style.LINE_COLOR,
            lw=style.WIRE_WIDTH,
        )
    )


FIGURE = style.Figure(draw=_draw, canvas=(-3.4, -5.5, 6.4, 1.0))

FIGURES = {
    "bus_timing": (FIGURE, ["lectures/L05/appendix/images/bus_timing.png"]),
}
