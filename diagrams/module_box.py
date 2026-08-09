"""Draws a module from its entity alone: the boundary, its ports, and its generics.

This is the picture the `or_gate` entity figure makes by hand, generalized. Nothing about
an architecture appears, which is the point: an exercise that asks for a module with given
inputs and outputs is fully specified by this drawing, and the implementation stays the
reader's to work out.

Conventions:

* A thin line is a `std_logic`, labeled with the port's name.
* A thick line is a `std_logic_vector`, labeled `name[hi:0]`.
* Arrows point into the boundary for inputs and away from it for outputs.
* Generics sit in a strip inside the top of the box, above a separator line.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Sequence

import schemdraw
import schemdraw.elements as elm

import style

# ----------------------------------------------------------------------------------------
# Layout, in schemdraw units.
# ----------------------------------------------------------------------------------------
MIN_BOX_WIDTH = 6.0  # Boxes share a width unless their generics need more.
BOX_PAD_X = 0.9  # Space either side of the generic text inside the box.
PORT_PITCH = 1.0  # Vertical distance between neighbouring ports.
PORT_PAD = 0.8  # Space above the first port and below the last.
GENERIC_PITCH = 0.7  # Vertical distance between generic lines.
GENERIC_PAD = 0.35  # Space above the first generic and below the last.
STUB = 1.05  # How far a port wire reaches outside the boundary.
LABEL_OFST = 0.30  # Gap between a port wire's outer end and its name.
TITLE_GAP = 0.35  # Gap between the boundary and the module name above it.
MARGIN = 0.35  # Blank canvas around everything.


@dataclass(frozen=True)
class Port:
    """One port of an entity.

    `width` is the number of bits: 1 for a `std_logic`, more for a `std_logic_vector`. A
    vector whose width comes from a generic gives the range as a string instead, e.g.
    `Port("button_n", "COUNT-1:0")`. `label` overrides the drawn text for the rare port that
    is neither, and `bus` then says whether to draw it thick.
    """

    name: str
    width: int | str = 1
    label: str | None = None
    bus: bool = False

    @property
    def is_bus(self) -> bool:
        return self.bus or isinstance(self.width, str) or self.width > 1

    @property
    def text(self) -> str:
        if self.label is not None:
            return self.label
        if isinstance(self.width, str):
            return f"{self.name}[{self.width}]"
        return self.name if self.width == 1 else f"{self.name}[{self.width - 1}:0]"


@dataclass(frozen=True)
class Entity:
    """A module's outside: its name, its ports in declaration order, and its generics."""

    name: str
    inputs: Sequence[Port]
    outputs: Sequence[Port]
    generics: Sequence[tuple[str, str]] = field(default=())  # (name, type)

    @property
    def generic_lines(self) -> list[str]:
        return [f"{name}: {kind}" for name, kind in self.generics]


@dataclass(frozen=True)
class _Layout:
    """Everything the drawing and the canvas are derived from."""

    width: float
    height: float
    ports_top: float  # Where the port area ends and the generic strip begins.
    input_ys: list[float]
    output_ys: list[float]
    title_y: float


def _port_ys(count: int, ports_top: float) -> list[float]:
    """Evenly pitched port positions, centered in the port area.

    Centering rather than top-aligning is what keeps a two-input, one-output module looking
    balanced when one side has fewer ports than the other.
    """
    span = (count - 1) * PORT_PITCH
    top = (ports_top + span) / 2
    return [top - i * PORT_PITCH for i in range(count)]


def _layout(entity: Entity) -> _Layout:
    ports_top = (max(len(entity.inputs), len(entity.outputs)) - 1) * PORT_PITCH + 2 * PORT_PAD

    lines = entity.generic_lines
    strip = 2 * GENERIC_PAD + len(lines) * GENERIC_PITCH if lines else 0.0
    height = ports_top + strip

    widest_generic = max((style.text_width(line) for line in lines), default=0.0)
    width = max(MIN_BOX_WIDTH, widest_generic + 2 * BOX_PAD_X)

    return _Layout(
        width=width,
        height=height,
        ports_top=ports_top,
        input_ys=_port_ys(len(entity.inputs), ports_top),
        output_ys=_port_ys(len(entity.outputs), ports_top),
        title_y=height + TITLE_GAP + style.text_height(style.TITLE_SIZE) / 2,
    )


def _canvas(entity: Entity, layout: _Layout) -> tuple[float, float, float, float]:
    """The smallest canvas that holds the box, its port labels, and its title."""
    left = max((style.text_width(p.text) for p in entity.inputs), default=0.0)
    right = max((style.text_width(p.text) for p in entity.outputs), default=0.0)
    title = style.text_width(entity.name, style.TITLE_SIZE)

    xmin = min(-(STUB + LABEL_OFST + left), layout.width / 2 - title / 2) - MARGIN
    xmax = max(layout.width + STUB + LABEL_OFST + right, layout.width / 2 + title / 2) + MARGIN
    ymax = layout.title_y + style.text_height(style.TITLE_SIZE) / 2 + MARGIN
    return (xmin, -MARGIN, xmax, ymax)


def _draw(entity: Entity, layout: _Layout, d: schemdraw.Drawing, ax) -> None:
    d.add(
        elm.Rect(corner1=(0, 0), corner2=(layout.width, layout.height), lw=style.BOX_WIDTH)
        .at((0, 0))
    )
    style.title(ax, entity.name, (layout.width / 2, layout.title_y))

    lines = entity.generic_lines
    if lines:
        d.add(elm.Line().at((0, layout.ports_top)).to((layout.width, layout.ports_top)))
        for i, line in enumerate(lines):
            y = layout.height - GENERIC_PAD - GENERIC_PITCH * (i + 0.5)
            style.text(ax, line, (layout.width / 2, y))

    for port, y in zip(entity.inputs, layout.input_ys):
        lw = style.BUS_WIDTH if port.is_bus else style.WIRE_WIDTH
        d.add(elm.Arrow(lw=lw).at((-STUB, y)).to((0, y)))
        style.text(ax, port.text, (-STUB - LABEL_OFST, y), halign="right")

    for port, y in zip(entity.outputs, layout.output_ys):
        lw = style.BUS_WIDTH if port.is_bus else style.WIRE_WIDTH
        d.add(elm.Arrow(lw=lw).at((layout.width, y)).to((layout.width + STUB, y)))
        style.text(ax, port.text, (layout.width + STUB + LABEL_OFST, y), halign="left")


def figure(entity: Entity) -> style.Figure:
    """A ready-to-render figure for one entity, sized to its own port list."""
    layout = _layout(entity)
    return style.Figure(
        draw=lambda d, ax: _draw(entity, layout, d, ax),
        canvas=_canvas(entity, layout),
    )
