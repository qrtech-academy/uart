"""The bit fields of the three flag registers, drawn as labelled cells.

A module box says what a block's ports are; this says what the bits inside a register word
mean, which is the other half of the contract in `uart_def` and in Part 2 of the protocol
spec. Only the low byte is drawn, because bits 31-8 are reserved in every register.

The data here is a transcription of `uart_def`, like `register_map.hpp` on the C++ side. If
a bit position changes, it changes in three places and this is one of them.
"""

from __future__ import annotations

import schemdraw.elements as elm

import style

# (register, {bit position: name}), most significant bit drawn leftmost.
ROWS: list[tuple[str, dict[int, str]]] = [
    ("STATUS", {0: "TX ready", 1: "RX valid", 2: "Error", 3: "TX idle"}),
    ("CTRL", {0: "enable", 1: "par lo", 2: "par hi", 3: "stop", 4: "RX IRQ", 5: "TX IRQ"}),
    ("ERROR_FLAGS", {0: "framing", 1: "parity", 2: "overrun"}),
]

BITS = 8  # Bits drawn per row; the rest of the word is reserved.
CELL_W = 2.3
CELL_H = 1.0
ROW_PITCH = 2.0
TOP = 6.0  # Bottom edge of the first row.
NUMBER_GAP = 0.5  # Between the top row and its bit numbers.
NOTE_GAP = 0.75  # Between the last row and the reserved-bits note.
LABEL_GAP = 0.35  # Between a row's name and its first cell.


def _draw(d, ax) -> None:
    for row, (name, bits) in enumerate(ROWS):
        y = TOP - row * ROW_PITCH
        style.text(ax, name, (-LABEL_GAP, y + CELL_H / 2), halign="right")

        for i in range(BITS):
            x = i * CELL_W
            d.add(
                elm.Rect(corner1=(x, y), corner2=(x + CELL_W, y + CELL_H), lw=style.BOX_WIDTH)
            )
            # A bit with no name is reserved in that register.
            style.text(ax, bits.get(BITS - 1 - i, "-"), (x + CELL_W / 2, y + CELL_H / 2))

        if row == 0:
            for i in range(BITS):
                style.text(
                    ax,
                    str(BITS - 1 - i),
                    (i * CELL_W + CELL_W / 2, y + CELL_H + NUMBER_GAP),
                )

    bottom = TOP - (len(ROWS) - 1) * ROW_PITCH
    style.text(
        ax,
        "bits 31-8 reserved: read 0, ignored on write",
        (0, bottom - NOTE_GAP),
        halign="left",
    )


# The widest row name sets how far the canvas reaches to the left of the cells.
_NAME_WIDTH = max(style.text_width(name) for name, _ in ROWS)

FIGURE = style.Figure(
    draw=_draw,
    canvas=(-(_NAME_WIDTH + LABEL_GAP + 0.35), 0.95, BITS * CELL_W + 0.35, 8.0),
)

# The map is introduced with `uart_def` in L01 and used by the register bank in L04, so both
# appendices embed the same figure.
FIGURES = {
    "reg_fields": (
        FIGURE,
        [
            "lectures/L01/appendix/images/reg_fields.png",
            "lectures/L04/appendix/images/reg_fields.png",
        ],
    )
}
