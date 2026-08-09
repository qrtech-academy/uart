#!/usr/bin/env bash
#
# Remove every generated build artifact: the GHDL work library from build_vhdl.sh (plus any
# work-obj*.cf left behind by running the three GHDL steps by hand in hw/), and the binaries
# built by build_cpp.sh.
#
# Usage:
#   ci/clean.sh
set -euo pipefail

# Root directory.
ROOT_DIR="$(dirname "${BASH_SOURCE[0]}")/.."

# Navigate to the root directory.
cd "$ROOT_DIR"

# Remove the generated GHDL "work" directory. Scoped to hw/, which is where all the VHDL lives, and
# read NUL-delimited so a path containing a space cannot split into extra arguments to rm -rf.
while IFS= read -r -d '' dir; do
    echo "==> $dir"
    rm -rf "$dir"
done < <(find hw -type d -name work -print0 | sort -z)

# Remove the design files GHDL writes when run by hand, without --workdir.
while IFS= read -r -d '' file; do
    echo "==> $file"
    rm -f "$file"
done < <(find hw -name 'work-obj*.cf' -print0 | sort -z)

# Remove each C++ demo's binary, via its own Makefile's clean target.
while IFS= read -r -d '' demo; do
    echo "==> $demo"
    make --no-print-directory -C "$demo" clean
done < <(find lectures fw -iname Makefile -printf '%h\0' | sort -z)
