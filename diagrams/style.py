"""Shared drawing style and rendering plumbing for the lecture diagrams.

Every visual constant lives here, so restyling every figure at once is a single edit.
Figure modules only describe geometry; they never touch colors, line weights, or output size.
"""

from __future__ import annotations

import io
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import matplotlib

matplotlib.use("Agg")  # Render straight to file; there is no display in WSL or in CI.

import matplotlib.pyplot as plt  # noqa: E402
import schemdraw  # noqa: E402
from PIL import Image  # noqa: E402

schemdraw.use("matplotlib")

# ----------------------------------------------------------------------------------------
# Colors
# ----------------------------------------------------------------------------------------
LINE_COLOR = "black"
ACCENT_COLOR = "#c00000"  # The architecture rectangle; the only non-black ink we use.
BACKGROUND = "white"

# ----------------------------------------------------------------------------------------
# Line weights
# ----------------------------------------------------------------------------------------
WIRE_WIDTH = 2.0
BUS_WIDTH = 4.5  # A std_logic_vector: one line carrying several bits.
BOX_WIDTH = 2.5
ACCENT_WIDTH = 2.0

# ----------------------------------------------------------------------------------------
# Text. Signal and module names are monospace so they read as the identifiers they are.
# ----------------------------------------------------------------------------------------
FONT = "monospace"
FONT_SIZE = 15
TITLE_SIZE = 17
TITLE_WEIGHT = "bold"

# ----------------------------------------------------------------------------------------
# Output geometry, in schemdraw units.
#
# A figure declares the canvas it is rendered onto instead of being cropped to its own
# contents. Figures that are read as a sequence can then share one canvas and line up pixel
# for pixel; a figure that has to grow with its content sizes its own.
#
# One unit is INCHES_PER_UNIT inches on the page, at every figure size, so a port label in a
# tall module box is exactly as big as one in a short box.
# ----------------------------------------------------------------------------------------
CANVAS = (-2.0, -0.35, 8.6, 5.19)  # (xmin, ymin, xmax, ymax); the or_gate sequence.
INCHES_PER_UNIT = 0.5
DPI = 130  # 10.6 x 5.54 units at 0.5 in/unit and 130 dpi = 689 x 360 px, as before.

# Line art on white uses a few hundred colors at most: two or three ink colors plus the
# greys and pinks antialiasing blends along each edge. Storing that as a palette rather than
# as 32-bit RGBA cuts the files to roughly a third, and for a figure already inside 256
# colors it is bit-for-bit lossless. Above that the loss is a few units on a handful of edge
# pixels, which is invisible at any zoom.
PALETTE_COLORS = 256

# A figure builder: adds elements to the drawing, and may use the raw matplotlib axes for
# the text, which schemdraw positions less predictably than we want here.
Builder = Callable[[schemdraw.Drawing, "plt.Axes"], None]


@dataclass(frozen=True)
class Figure:
    """One drawable figure: how to draw it, and the canvas it is drawn onto."""

    draw: Builder
    canvas: tuple[float, float, float, float] = field(default=CANVAS)


# The text is monospace, so a string's width is its length times one character. DejaVu Sans
# Mono advances 0.602 em per character; 72 points to the inch.
CHAR_ASPECT = 0.602


def text_width(string: str, size: float = FONT_SIZE) -> float:
    """Width of `string` in canvas units, for laying out around a label."""
    return len(string) * size * CHAR_ASPECT / (72 * INCHES_PER_UNIT)


def text_height(size: float = FONT_SIZE) -> float:
    """Cap-to-descender height of a line of text, in canvas units."""
    return size / (72 * INCHES_PER_UNIT)


def text(
    ax,
    string: str,
    pos: tuple[float, float],
    halign: str = "center",
    valign: str = "center",
    size: float = FONT_SIZE,
    weight: str = "normal",
) -> None:
    """Draw text at an exact point on the canvas.

    Goes through matplotlib rather than schemdraw so that a label's position is the point
    given and nothing else, and so that bold is available; schemdraw's text has no weight.
    """
    ax.text(
        pos[0],
        pos[1],
        string,
        fontsize=size,
        family=FONT,
        weight=weight,
        color=LINE_COLOR,
        ha=halign,
        va=valign,
    )


def title(ax, string: str, pos: tuple[float, float]) -> None:
    """Draw a module name above a figure."""
    text(ax, string, pos, size=TITLE_SIZE, weight=TITLE_WEIGHT)


def render(figure: Figure, paths: list[Path]) -> None:
    """Draw a figure and write it to every path in `paths`.

    A figure with more than one path is one that several lectures embed; writing all the
    copies from a single source is what keeps them identical.
    """
    xmin, ymin, xmax, ymax = figure.canvas
    fig, ax = plt.subplots(
        figsize=((xmax - xmin) * INCHES_PER_UNIT, (ymax - ymin) * INCHES_PER_UNIT)
    )
    try:
        drawing = schemdraw.Drawing(canvas=ax)
        drawing.config(
            fontsize=FONT_SIZE, font=FONT, color=LINE_COLOR, lw=WIRE_WIDTH
        )
        figure.draw(drawing, ax)
        drawing.draw(show=False, canvas=ax)

        # Pin the view to the declared canvas instead of letting matplotlib fit the
        # content, and drop every margin so the saved pixels are exactly the canvas.
        ax.set_xlim(xmin, xmax)
        ax.set_ylim(ymin, ymax)
        ax.set_aspect("equal")
        ax.axis("off")
        fig.subplots_adjust(left=0, bottom=0, right=1, top=1)

        buffer = io.BytesIO()
        fig.savefig(buffer, format="png", dpi=DPI, facecolor=BACKGROUND)
    finally:
        plt.close(fig)

    # The background is opaque, so dropping the alpha channel costs nothing. Median cut is
    # deterministic, which keeps a rebuild byte-identical.
    image = Image.open(buffer).convert("RGB").quantize(colors=PALETTE_COLORS)
    for path in paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, "PNG", optimize=True)
