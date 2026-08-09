# Build everything: the host-side C++ (the driver, its host tests and the demo main), then the VHDL
# peripheral.
build: build-cpp build-vhdl

# Build the host-side C++ and run its tests (QAcademy Test).
build-cpp:
	@bash ci/build_cpp.sh

# Analyze, elaborate, and simulate the VHDL peripheral with GHDL.
build-vhdl:
	@bash ci/build_vhdl.sh

# Remove all generated build artifacts.
clean:
	@bash ci/clean.sh

# Format this course's own sources in place: C/C++ through clang-format, and trailing whitespace
# stripped from the VHDL in hw/. libs/ and temp/ are skipped.
format:
	@bash ci/format.sh

# Check formatting without modifying any files; fails if something isn't formatted.
format-check:
	@bash ci/format.sh --check

# Redraw the generated module diagrams. Deliberately not part of build: the PNGs are committed
# so GitHub renders the lectures without one, and CI has no Python environment. Optional:
# FIGURE=<name>. See diagrams/README.md for the one-time venv setup.
diagrams:
	@test -x .venv/bin/python || { \
	  echo "No Python environment at .venv/bin/python. Create it once with:"; \
	  echo "  python3 -m venv .venv"; \
	  echo "  .venv/bin/pip install -r diagrams/requirements.txt"; \
	  exit 1; }
	@.venv/bin/python diagrams/build.py $(FIGURE)

.PHONY: build build-cpp build-vhdl clean format format-check diagrams
