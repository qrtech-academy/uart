# Build the book: vector figures from diagrams/, then two LuaLaTeX passes, the second for the
# contents and the references.
#
#   make                   build uart.pdf, dated today
#   make VERSION=book-v2   the same, with the release's version on the title page
#   make figures           render the figures only, into build/figures
#   make clean             remove everything the build writes
#
# The figures are drawn by the same Python that draws the lectures' PNGs, and the provided VHDL
# printed in Chapter 1 is typeset straight from hw/, so a change to either is a change to the book
# on the next build. The figures need the repository's Python environment: see diagrams/README.md
# for the one-time setup, or pass PYTHON= an interpreter that has the pinned packages, as the
# release workflow does.

ROOT     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BOOK     := $(ROOT)/book
BUILD    ?= $(BOOK)/build
PYTHON   ?= $(ROOT)/.venv/bin/python
VERSION  ?=
LATEX    := lualatex -interaction=nonstopmode -halt-on-error -file-line-error \
            -output-directory=$(BUILD)
# The book, with its version and its figures' directory defined before anything is read;
# -jobname keeps the output book.pdf.
BOOKTEX  := $(LATEX) -jobname=book \
            '\def\bookversion{$(VERSION)}\def\figurepath{$(BUILD)/figures/}\input{book.tex}'

SOURCES  := book.tex uartbook.sty uartbook.lua \
            $(wildcard front/*.tex chapters/*/*.tex back/*.tex back/*/*.tex)
CODE     := $(shell cd $(ROOT) && git ls-files 'hw/*.vhd' | sed 's|^|$(ROOT)/|')
# Every figure diagrams/build.py knows, in one run: a dozen PDFs take a few seconds, and the
# builders import each other, so any change to diagrams/ redraws the lot.
FIGSTAMP := $(BUILD)/figures/.stamp

.PHONY: all figures clean FORCE

all: uart.pdf

figures: $(FIGSTAMP)

$(FIGSTAMP): figures.py $(wildcard $(ROOT)/diagrams/*.py)
	@if [ ! -x "$(PYTHON)" ] && ! command -v "$(PYTHON)" >/dev/null; then \
	  echo "No Python at $(PYTHON). Create the environment once with:"; \
	  echo "  python3 -m venv .venv"; \
	  echo "  .venv/bin/pip install -r diagrams/requirements.txt"; \
	  exit 1; \
	fi
	$(PYTHON) $(BOOK)/figures.py $(BUILD)/figures
	@touch $@

# The version the last build was made for. The file is rewritten only when VERSION changes, so a
# new version, or none after one, rebuilds the title page and nothing else does.
$(BUILD)/version: FORCE
	@mkdir -p $(BUILD)
	@echo '$(VERSION)' | cmp -s - $@ || echo '$(VERSION)' > $@

uart.pdf: $(SOURCES) $(CODE) $(FIGSTAMP) $(BUILD)/version
	@mkdir -p $(BUILD)
	cd $(BOOK) && $(BOOKTEX) >/dev/null || (tail -40 $(BUILD)/book.log; exit 1)
	cd $(BOOK) && $(BOOKTEX) >/dev/null || (tail -40 $(BUILD)/book.log; exit 1)
	@grep -E "^(Overfull|Underfull)|Warning" $(BUILD)/book.log | sort | uniq -c | sort -rn | head -20 || true
	@! grep -q "There were undefined references" $(BUILD)/book.log || \
	    (echo "error: undefined references; see $(BUILD)/book.log"; exit 1)
	cp $(BUILD)/book.pdf $@

clean:
	rm -rf $(BUILD) uart.pdf
