# The Book
The course typeset as a book with LuaLaTeX: ten chapters, one per lecture, in the course's two
parts, then the appendices: the UART register protocol, the answers to every exercise part that is
not code, and the two self-assessment papers with their model answers. The VHDL and C++ the
exercises ask for is not answered: the provided testbenches and host suites are the check.

---

## Building it

```bash
sudo apt -y install make texlive-luatex texlive-latex-extra fonts-texgyre fonts-texgyre-math \
                    fonts-dejavu-core poppler-utils
python3 -m venv .venv && .venv/bin/pip install -r diagrams/requirements.txt   # Once, for figures.
make -C book                   # Writes book/uart.pdf, dated today.
make -C book VERSION=book-v2   # The same, with the version on the title page.
make -C book figures           # Only renders the figures, into book/build/figures.
make -C book clean             # Removes book/build/ and the PDF.
```

The figures are the lectures' own: [`figures.py`](./figures.py) imports the registry in
[`diagrams/build.py`](../diagrams/build.py) and renders every figure it lists as a vector PDF
instead of a PNG, so the book needs the same Python environment as `make diagrams`, described in
[`diagrams/README.md`](../diagrams/README.md). `PYTHON=python3` points the build at an interpreter
that has the pinned packages some other way, and `BUILD=` puts everything the build writes somewhere
other than `book/build`.

The build then runs LuaLaTeX twice, so the contents and the cross-references settle, prints any
overfull or underfull lines and LaTeX warnings it found, and fails if a reference is left undefined.
A clean build prints nothing after the two `lualatex` lines except a handful of mildly underfull
ones.

---

## Releasing a new edition
The PDF is committed, as `book/uart.pdf`, so the repository always holds a readable copy; rebuild it
with `make -C book` and commit it along with any change to the book. Each edition is also published
as a GitHub release, with its version on the title page. Push a tag named `book-v*`:

```bash
git tag book-v2
git push origin book-v2
```

The [Book workflow](../.github/workflows/book.yml) then builds the PDF with the tag on its title
page and attaches it to a release of the same name.

---

## What is where

```text
book.tex                The book: front matter, two parts of five chapters, appendices, in order.
uartbook.sty            Every visual decision: page, type, colours, code blocks, figures, exercises.
uartbook.lua            How \code{...} typesets inline code (#, \n and line breaks).
figures.py              Renders the figures in diagrams/ as vector PDFs for the book.
front/                  Title pages and preface.
chapters/NN/            Chapter NN: chapter.tex (the opener), one file per appendix of lecture
                        LNN, summary.tex (the review) and the exercises.
back/protocol.tex       Appendix A: the UART register protocol.
back/answers/           Appendix B: the answers to the exercise parts that are not code, one file
                        per chapter that has any.
back/exam/              Appendices C to G: the papers and their model answers.
```

Every `.tex` file typeset from course material starts with a comment naming its source, for
example:

```tex
% Section 2.1, from lectures/L02/appendix/a_baud_gen.md.
```

---

## Updating the content
The course material is the source of truth, and the book follows it. **Two kinds of content behave
differently:**
* **The figures and the provided VHDL update themselves.** The book does not contain the figures; it
  renders them from `diagrams/` on every build. The two provided files printed in Chapter 1,
  `hw/uart_def.vhd` and `hw/reset_sync.vhd`, are typeset straight from `hw/`
  (`\vhdlfile{hw/...}`). A change to either is in the book on the next build, with nothing to edit
  here.
* **Prose and the code in the text do not.** A chapter's text is a typeset copy of its lecture's
  markdown. When you change a lecture appendix, make the same change in the `.tex` file whose header
  names it. The same holds for `protocol/uart_register_protocol.md` and `back/protocol.tex`, and for
  `exam/*.md` and `back/exam/`.
* **The answers are verified, not only written.** Where an answer in `back/answers/` says what a
  testbench or a suite reports when a design is broken on purpose, that is what a design built to the
  chapter's specification reported when it was broken in exactly that way. When an exercise, a
  testbench or a suite changes, re-check the answers that quote it.

A few conventions, so an edit reads like the rest of the book:
* Code blocks: `vhdlcode` (VHDL), `cppcode` (C++), `shell`, `makecode` (Makefiles), `console` (tool
  output, directory trees, pseudo-code, plain text), and `textdrawing` for plain text with characters
  outside ASCII.
* Inline code: `\code{...}`, written exactly as in the source. Inside it, write `\%` for `%`, `\{` or
  `\}` for an unbalanced brace, `\\` for a backslash, and `\#` for `#` in a heading or caption. File
  names are `\file{...}`.
* References: `\secref{c5:app:a}` is the section typeset from appendix A of L05, `\chapref{3}` is
  "Chapter 3", `\secref{proto:part2}` is Part 2 of the protocol, and `Exercise~\ref{c4:ex:1}` is
  exercise 1 of L04, which the book numbers 4.1. Refer to exercises by label, never by number.
* Exercises: `\exerciseset{Title}` for a lecture's exercise set, `\exercise{Title}{Kind}` for one
  exercise, where the kind is one of VHDL, C++, Reasoning and Bench and picks the tag's colour,
  `\xpart{a}` for a lettered part (with `\parttitle{...}` when it has a title), and `\task{...}` for
  a titled sub-heading.
* Answers: `\solution{c4:ex:1}{Title}`, then `\ans{b}` for each part answered.
* Figures: `\bookfigure{name}{caption}{cN:fig:name}`, where the name is the one `diagrams/build.py`
  registers, and `\modulefigure{name}` where an exercise reprints a module box already shown. A new
  figure needs nothing in the book's Makefile, which renders everything the registry lists.
* A new lecture appendix is a new file in `chapters/NN/`, `\input` from that chapter's
  `chapter.tex`.

---

## License
The book, its text and figures and the PDF built from them, is licensed under
[CC BY-NC-SA 4.0](../LICENSE-CONTENT), like the course material it is typeset from. This directory's
build files (`uartbook.sty`, `uartbook.lua`, `figures.py`, `Makefile`) are released under the
repository's [MIT License](../LICENSE), like all the code in the course, and so may the code
examples printed in the book be used.
