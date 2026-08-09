"""The inside of `uart_regs`: the blocks it holds and what connects them.

This is the one figure in the set that shows an architecture rather than an outside, and it
is deliberate. `uart_regs` is not a state machine a student can hold in their head from the
port list alone - it is two queues facing opposite directions, three stored registers, a
decode and a read mux - and L04 Appendix A now spells that structure out in prose. The
figure is that prose in one picture; the exercises still ask for every line of the VHDL.

Conventions follow the module boxes: thin line for a `std_logic`, thick for a vector, and
the accent rectangle for the module boundary.
"""

from __future__ import annotations

import schemdraw.elements as elm

import style

# ----------------------------------------------------------------------------------------
# Layout. Two columns of blocks: the bus-facing side on the left, the storage on the right,
# with a clear corridor between them for the decode's fan-out and the flag bus.
# ----------------------------------------------------------------------------------------
OUTER = (0.0, 0.0, 13.0, 8.6)

# name -> (x1, y1, x2, y2, lines of text)
# The read mux is wide and sits along the bottom, so its three sources drop straight into it
# instead of threading back through the corridor.
BLOCKS: dict[str, tuple[float, float, float, float, tuple[str, ...]]] = {
    "decode": (1.5, 6.5, 4.3, 7.9, ("decode", "(reg_idx)")),
    "status": (1.5, 4.2, 4.3, 5.6, ("STATUS", "(computed)")),
    "mux": (1.5, 0.9, 6.6, 2.3, ("read mux",)),
    "txf": (7.2, 6.5, 10.6, 7.9, ("TX FIFO", "8 x 8")),
    "regs": (7.2, 4.2, 10.6, 5.6, ("ctrl_reg", "baud_div_reg", "err_flags")),
    "rxf": (7.2, 1.3, 10.6, 2.7, ("RX FIFO", "8 x 8")),
}

LINE_PITCH = 0.42  # Between stacked lines of text inside a block.
STUB = 1.75  # How far a port wire reaches outside the module boundary.
LABEL_GAP = 0.3  # Between a port wire's outer end and its name.
FLAG_X = 5.7  # The vertical the four STATUS inputs share.


def _block(d, ax, key: str) -> None:
    x1, y1, x2, y2, lines = BLOCKS[key]
    d.add(elm.Rect(corner1=(x1, y1), corner2=(x2, y2), lw=style.BOX_WIDTH))
    middle = (y1 + y2) / 2 + (len(lines) - 1) * LINE_PITCH / 2
    for i, line in enumerate(lines):
        style.text(ax, line, ((x1 + x2) / 2, middle - i * LINE_PITCH))


def _route(d, points: list[tuple[float, float]], arrow: bool = True, bus: bool = False) -> None:
    """Draw an orthogonal run through `points`, arrowhead on the last segment."""
    lw = style.BUS_WIDTH if bus else style.WIRE_WIDTH
    for i in range(len(points) - 1):
        last = i == len(points) - 2
        element = elm.Arrow if (arrow and last) else elm.Line
        d.add(element(lw=lw).at(points[i]).to(points[i + 1]))


def _port(d, ax, name: str, y: float, side: str, outward: bool, bus: bool = False) -> None:
    """One port: a wire piercing the boundary, and its name outside."""
    if side == "left":
        outer, inner = -STUB, BLOCKS["decode"][0]
        halign = "right"
        label_x = outer - LABEL_GAP
    else:
        outer, inner = OUTER[2] + STUB, BLOCKS["txf"][2]
        halign = "left"
        label_x = outer + LABEL_GAP

    start, end = ((inner, y), (outer, y)) if outward else ((outer, y), (inner, y))
    _route(d, [start, end], bus=bus)
    style.text(ax, name, (label_x, y), halign=halign)


def _draw(d, ax) -> None:
    x1, y1, x2, y2 = OUTER
    d.add(
        elm.Rect(corner1=(x1, y1), corner2=(x2, y2), lw=style.ACCENT_WIDTH)
        .color(style.ACCENT_COLOR)
    )
    style.title(ax, "uart_regs", ((x1 + x2) / 2, y2 + 0.35 + style.text_height(style.TITLE_SIZE) / 2))

    for key in BLOCKS:
        _block(d, ax, key)

    # The register bus, on the left.
    _port(d, ax, "reg_write", 7.6, "left", outward=False)
    _port(d, ax, "reg_addr", 7.2, "left", outward=False, bus=True)
    _port(d, ax, "reg_wdata", 6.8, "left", outward=False, bus=True)
    _port(d, ax, "reg_rdata", 1.6, "left", outward=True, bus=True)

    # The datapath, on the right.
    _port(d, ax, "tx_byte", 7.6, "right", outward=True, bus=True)
    _port(d, ax, "tx_empty", 7.2, "right", outward=True)
    _port(d, ax, "tx_pop", 6.8, "right", outward=False)
    _port(d, ax, "baud_div", 5.2, "right", outward=True, bus=True)
    _port(d, ax, "frame_err", 4.8, "right", outward=False)
    _port(d, ax, "rx_byte", 2.4, "right", outward=False, bus=True)
    _port(d, ax, "rx_push", 2.0, "right", outward=False)
    _port(d, ax, "rx_full", 1.6, "right", outward=True)

    # What the decode drives: one push, one pop, and the config writes.
    _route(d, [(4.3, 7.2), (7.2, 7.2)])
    style.text(ax, "tx_push", (5.75, 7.45))
    _route(d, [(4.3, 6.9), (5.2, 6.9), (5.2, 5.0), (7.2, 5.0)])
    _route(d, [(4.3, 6.65), (6.9, 6.65), (6.9, 2.6), (7.2, 2.6)])
    style.text(ax, "rx_pop", (7.0, 3.4), halign="left")

    # The flag bus: four levels in, one STATUS word out. Dots are real joins.
    d.add(elm.Line(lw=style.WIRE_WIDTH).at((FLAG_X, 2.5)).to((FLAG_X, 6.75)))
    for tap_y in (6.75, 4.9, 2.5):
        _route(d, [(7.2, tap_y), (FLAG_X, tap_y)], arrow=False)
        d.add(elm.Dot().at((FLAG_X, tap_y)))
    _route(d, [(OUTER[2] + STUB, 6.0), (FLAG_X, 6.0)], arrow=False)
    d.add(elm.Dot().at((FLAG_X, 6.0)))
    style.text(ax, "tx_busy", (OUTER[2] + STUB + LABEL_GAP, 6.0), halign="left")
    _route(d, [(FLAG_X, 5.3), (4.3, 5.3)])
    style.text(ax, "flags", (FLAG_X - 0.15, 3.6), halign="right")

    # What the read mux selects between: the status word, the stored registers, and the RX
    # front byte. All three drop into the wide mux rather than crossing the corridor.
    _route(d, [(2.6, 4.2), (2.6, 2.3)])
    style.text(ax, "status_reg", (2.5, 3.3), halign="right")
    _route(d, [(7.2, 4.35), (6.3, 4.35), (6.3, 2.3)], bus=True)
    _route(d, [(7.2, 1.7), (6.6, 1.7)], bus=True)


FIGURE = style.Figure(
    draw=_draw,
    canvas=(
        -(STUB + LABEL_GAP + style.text_width("reg_wdata") + 0.3),
        -0.35,
        OUTER[2] + STUB + LABEL_GAP + style.text_width("frame_err") + 0.3,
        9.6,
    ),
)

FIGURES = {
    "regs_internals": (FIGURE, ["lectures/L04/appendix/images/regs_internals.png"]),
}
