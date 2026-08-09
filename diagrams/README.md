# Diagrams

The module figure at the top of each "Designing `<module>.vhd`" appendix is drawn from code,
so changing a port is an edit and a rebuild rather than a redraw. One figure per VHDL entity
in `hw/`, showing the module's outside only: boundary, ports, generics, nothing of the
architecture. For a module a student writes, that is exactly the contract the exercise sets.

The generated PNGs stay committed. GitHub renders the lectures straight from the repo, so
nothing here runs in CI; this is an authoring tool you run when an entity changes.

## Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r diagrams/requirements.txt
```

## Rebuilding

```bash
make diagrams                                  # every figure, into the lecture trees
.venv/bin/python diagrams/build.py --list      # what can be built
make diagrams FIGURE=uart_regs                 # just one
.venv/bin/python diagrams/build.py --outdir /tmp/preview   # look before overwriting
```

`--outdir` writes `<figure>.png` flat into a directory of your choice and leaves the repo
untouched, which is the sane way to iterate on a figure.

## Layout

| File | What it holds |
| --- | --- |
| `style.py` | Every color, line weight, font, and the output scale. Restyling all figures is one edit here. |
| `module_box.py` | Draws any module from its entity alone: boundary, ports, generics. |
| `modules.py` | The entity of every VHDL module in `hw/`. |
| `build.py` | Figure name to figure plus output path, and the command line. |

`style.py` and `module_box.py` are shared verbatim with the digital-design-vhdl course, so a
fix to either belongs in both.

## Adding a module

Add an `Entity` to `modules.py` and list it under its lecture in `BY_LECTURE`. `build.py`
picks it up automatically and writes `lectures/<lecture>/appendix/images/<name>.png`. Embed
that in the appendix beside the module's port table, copying the line already there in the
neighbouring appendices: a Markdown image with alt text ``Module `<name>` `` pointing at
`./images/<name>.png`.

Ports go in **declaration order**. The testbenches in `hw/` bind positionally, so a
transposed pair of same-type pins analyzes cleanly and fails only in simulation; the order
here has to match the port table in the appendix and the `port map` in
`hw/<module>_tb.vhd`, and for a module that exists, `hw/<module>.vhd` is the final word.

```python
UART_TX = Entity(
    "uart_tx",
    [P("clock"), P("reset_s2_n"), P("baud_tick"), P("start"), P("data", 8)],
    [P("tx"), P("busy"), P("done")],
)
```

A port's width is its bit count: 1 draws a thin `std_logic` line labeled with the name, more
draws a thick line labeled `name[hi:0]`. A width that comes from a generic is written as a
string, `P("async_in", "COUNT-1:0")`. A port that is neither a `std_logic` nor a vector takes
a `label` override plus `bus=` to say how thick to draw it; `baud_gen`'s `div` is the only
one.

## Notes

* A figure sizes its own canvas from its port list, but always at the same units-per-inch, so a
  label on `uart_regs` (fifteen ports) is exactly as big as one on `reset_sync` (three).
* Figures are written as palette PNGs (`style.PALETTE_COLORS`), not RGBA. Line art on white uses a
  few hundred colors at most, so this costs nothing visually and roughly halves what gets committed.
  Median cut is deterministic, so a rebuild stays byte-identical.
* The figures are black on white, which is hard to read in GitHub's dark theme. So is every other
  image in this repo. If that ever needs fixing, it is a change to the colors in `style.py`.
