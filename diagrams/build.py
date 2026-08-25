#!/usr/bin/env python3
"""Regenerate the lecture diagrams.

    python3 diagrams/build.py                     # every figure, into the lecture trees
    python3 diagrams/build.py baud_gen            # one figure
    python3 diagrams/build.py --outdir /tmp/x     # preview, without touching the repo

Adding a figure: add an `Entity` to modules.py and list it under its lecture in BY_LECTURE.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bus_timing  # noqa: E402
import module_box  # noqa: E402
import modules  # noqa: E402
import reg_fields  # noqa: E402
import regs_internals  # noqa: E402
import style  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

# Figures that are not one entity's box. A module box is named and placed by its entity, but
# these are not tied to a single entity, so each module declares its own name and the
# repo-relative paths it is embedded at - more than one, where several appendices share it.
EXTRA_FIGURES: dict[str, tuple[style.Figure, list[str]]] = {
    **reg_fields.FIGURES,
    **regs_internals.FIGURES,
    **bus_timing.FIGURES,
}

# figure name -> (figure, output paths). One module figure per VHDL entity, in the appendix of
# the lecture that designs it - and in any later lecture's appendix that reprints its port table,
# which is why the paths accumulate rather than overwrite.
FIGURES: dict[str, tuple[style.Figure, list[Path]]] = {}
for _lecture, _entities in modules.BY_LECTURE.items():
    for _entity in _entities:
        _path = ROOT / "lectures" / _lecture / "appendix/images" / f"{_entity.name}.png"
        if _entity.name in FIGURES:
            FIGURES[_entity.name][1].append(_path)
        else:
            FIGURES[_entity.name] = (module_box.figure(_entity), [_path])
FIGURES.update(
    {name: (figure, [ROOT / p for p in paths]) for name, (figure, paths) in EXTRA_FIGURES.items()}
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "figures",
        nargs="*",
        metavar="FIGURE",
        help="Figures to build. Default: all of them.",
    )
    parser.add_argument(
        "--outdir",
        type=Path,
        help="Write <FIGURE>.png here instead of into the lecture trees.",
    )
    parser.add_argument(
        "--list", action="store_true", help="List the known figures and exit."
    )
    args = parser.parse_args()

    if args.list:
        for name in FIGURES:
            print(name)
        return 0

    names = args.figures or list(FIGURES)
    unknown = [name for name in names if name not in FIGURES]
    if unknown:
        parser.error(
            f"unknown figure(s): {', '.join(unknown)}\nknown: {', '.join(FIGURES)}"
        )

    for name in names:
        figure, paths = FIGURES[name]
        if args.outdir:
            paths = [args.outdir / f"{name}.png"]
        style.render(figure, paths)
        for path in paths:
            print(f"wrote {path.relative_to(ROOT) if ROOT in path.parents else path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
