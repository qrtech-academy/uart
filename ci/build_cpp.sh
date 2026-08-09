#!/usr/bin/env bash
#
# Build the C++ this course produces, and run its host tests.
#
# Every self-contained demo is a directory with its own Makefile. In this course that is fw/ alone
# (the driver, its host tests, and the AVR port); lectures/ is still scanned, because sibling
# courses ship small per-lecture demos there, but this one keeps everything in fw/ and the scan
# finds nothing. Each Makefile found is built with its "build" target so the flags stay in one
# place, then, if it defines a "test" target, tested with QAcademy Test. The AVR port under fw/avr cross-compiles with avr-gcc and is
# excluded here - it is built and flashed separately (see fw/README.md); host CI only builds
# what runs on the host.
#
# Code arrives lecture by lecture, so most of the tree is missing for most of the course; a fresh
# scaffold with no Makefiles yet simply reports that there is nothing to build.
#
# Usage:
#   ci/build_cpp.sh
set -euo pipefail

# Root directory.
ROOT_DIR="$(dirname "${BASH_SOURCE[0]}")/.."

################################################################################
# Terminate the script if a C++ compiler is not installed.
################################################################################
check_compiler() {
    if ! command -v g++ &> /dev/null
    then
        echo "error: g++ not found. Install it, e.g. 'sudo apt -y install g++'." >&2
        exit 1
    fi
}

# Navigate to the root directory.
cd "$ROOT_DIR"

# Check if a C++ compiler is installed.
check_compiler

# Find every host-side demo, skipping the AVR firmware (cross-compiled separately).
mapfile -t -d '' DEMOS < <(find lectures fw -path '*/avr' -prune -o -iname Makefile -printf '%h\0' | sort -z)

if [ "${#DEMOS[@]}" -eq 0 ]; then
    echo "No host C++ code yet - nothing to build. (Code arrives lecture by lecture.)"
    exit 0
fi

processed=0
tested=0
for demo in "${DEMOS[@]}"; do
    echo "==> $demo"
    make --no-print-directory -C "$demo" build
    processed=$((processed + 1))

    # Run the test suite if the demo defines one (QAcademy Test).
    #
    # The target is detected by reading the Makefile, not by running `make -n test`. A dry run is
    # not safe here: make executes any recipe line containing $(MAKE) even under -n, so the probe
    # used to build and run the whole suite with its output discarded. Worse, a *failing* suite
    # made the probe non-zero, so the real `make test` below was skipped and CI reported success.
    if grep -qE '^test[[:space:]]*:' "$demo/Makefile"; then
        make --no-print-directory -C "$demo" test
        tested=$((tested + 1))
    fi
done

echo
# "processed" rather than "built": early in the course both targets legitimately report there is
# nothing to do, and a summary claiming they were built and tested would contradict the lines above.
echo "$processed C++ directory(ies) processed, $tested with a test target."
