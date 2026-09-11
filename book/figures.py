#!/usr/bin/env python3
"""Render the lecture figures as vector PDFs for the book.

    .venv/bin/python book/figures.py OUTDIR [FIGURE...]

The lectures embed 130 dpi PNGs, which is right for a screen and soft on paper. The drawings
themselves are vector, so this reuses the figure registry in diagrams/build.py unchanged and swaps
only the last step: matplotlib writes a PDF instead of a palette PNG. Nothing in diagrams/ is
modified, and a figure changed there is changed here on the next build. With no FIGURE named,
every figure diagrams/build.py knows is written.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "diagrams"))

import build  # noqa: E402
import style  # noqa: E402  (imports matplotlib with the Agg backend)
import matplotlib  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402
import schemdraw  # noqa: E402

# Embed the monospace face as TrueType rather than Type 3, so the text in a figure is real text:
# searchable, selectable, and the same DejaVu Sans Mono as the code in the book around it.
matplotlib.rcParams["pdf.fonttype"] = 42


def render_pdf(figure: style.Figure, path: Path) -> None:
    """Draw one figure onto its declared canvas and write it as a PDF.

    The same steps as style.render, less the palette pass, which only a PNG needs.
    """
    xmin, ymin, xmax, ymax = figure.canvas
    fig, ax = plt.subplots(
        figsize=((xmax - xmin) * style.INCHES_PER_UNIT, (ymax - ymin) * style.INCHES_PER_UNIT))
    try:
        drawing = schemdraw.Drawing(canvas=ax)
        drawing.config(fontsize=style.FONT_SIZE, font=style.FONT, color=style.LINE_COLOR,
                       lw=style.WIRE_WIDTH)
        figure.draw(drawing, ax)
        drawing.draw(show=False, canvas=ax)
        ax.set_xlim(xmin, xmax)
        ax.set_ylim(ymin, ymax)
        ax.set_aspect("equal")
        ax.axis("off")
        fig.subplots_adjust(left=0, bottom=0, right=1, top=1)
        # No creation date, so a rebuild of an unchanged figure is an unchanged file.
        fig.savefig(path, format="pdf", facecolor=style.BACKGROUND,
                    metadata={"CreationDate": None})
    finally:
        # Close even on failure; matplotlib figures are a process-wide resource.
        plt.close(fig)


def main() -> int:
    """Render each figure named on the command line, or every figure, into OUTDIR as NAME.pdf."""
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    names = sys.argv[2:] or list(build.FIGURES)
    unknown = [name for name in names if name not in build.FIGURES]
    if unknown:
        print(f"unknown figure(s): {', '.join(unknown)}", file=sys.stderr)
        return 2
    for name in names:
        render_pdf(build.FIGURES[name][0], outdir / f"{name}.pdf")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
