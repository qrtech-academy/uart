#!/usr/bin/env bash
#
# Format (or check the formatting of) the sources this course owns.
#
# C/C++ goes through clang-format. VHDL has no equivalent tool here, so it gets the one rule worth
# enforcing mechanically: no trailing whitespace. That is not cosmetic pedantry. Trailing spaces
# produce diff noise that hides real changes, and in a course where students diff their work against
# a reference, noise is expensive.
#
# Two directories are skipped for C/C++. temp/ is scratch and gitignored. libs/ holds submodules,
# whose sources belong to their own repository and carry their own .clang-format; reformatting them
# here would dirty the submodule for a style decision that is not this repository's to make.
#
# Usage:
#   ci/format.sh          Format files in place.
#   ci/format.sh --check  Fail if any file is not already formatted.
set -euo pipefail

# Root directory.
ROOT_DIR="$(dirname "${BASH_SOURCE[0]}")/.."

################################################################################
# Terminate the script if clang-format is not installed.
# Globals:
#   None
# Arguments:
#   None
################################################################################
check_clang_format() {
    if ! command -v clang-format &> /dev/null
    then
        echo "error: clang-format not found. Install it, e.g. 'sudo apt -y install clang-format'." >&2
        exit 1
    fi
}

################################################################################
# Find C/C++ files and store them in the given array. Skips temp/ and libs/
# (see the file header).
# Globals:
#   None
# Arguments:
#   $1 - Name of the array variable to populate with file paths.
################################################################################
select_files() {
    local -n out=$1
    mapfile -t out < <(find * -path temp -prune -o -path libs -prune -o \
        \( -name "*.h" -o -name "*.hpp" -o -name "*.c" -o -name "*.cpp" \) -print)
}

################################################################################
# Find VHDL files and store them in the given array. All VHDL in this course
# lives in hw/, so the search is scoped there; hw/work/ holds GHDL's generated
# artifacts and is pruned.
# Globals:
#   None
# Arguments:
#   $1 - Name of the array variable to populate with file paths.
################################################################################
select_vhdl_files() {
    local -n out=$1
    out=()
    if [ -d hw ]; then
        mapfile -t out < <(find hw -path hw/work -prune -o -name "*.vhd" -print | sort)
    fi
}

################################################################################
# Strip trailing whitespace from the given VHDL files, or check for it.
# Globals:
#   None
# Arguments:
#   $1 - Run command, e.g. --check. Empty string strips in place.
#   $2 - Name of the array variable containing files to process.
################################################################################
strip_vhdl_whitespace() {
    local arg="$1"
    local -n files=$2

    if [[ "${arg:-}" == "--check" ]]
    then
        local offenders=0
        for file in "${files[@]}"
        do
            # grep -n gives file:line, which is what makes the failure actionable.
            if grep -nP '[ \t]+$' "$file" | sed "s|^|$file:|" >&2
            then
                offenders=$((offenders + 1))
            fi
        done
        if [ "$offenders" -gt 0 ]
        then
            echo "error: trailing whitespace in $offenders VHDL file(s); run ci/format.sh." >&2
            return 1
        fi
        echo "Checked ${#files[@]} VHDL file(s); no trailing whitespace."
    else
        local count=0
        for file in "${files[@]}"
        do
            if grep -qP '[ \t]+$' "$file"
            then
                # GNU coreutils is assumed throughout this course (Linux/WSL): `sed -i` with no
                # backup suffix and the `grep -nP` above are both GNU spellings.
                sed -i 's/[[:space:]]*$//' "$file"
                echo "Stripped trailing whitespace: $file"
                count=$((count + 1))
            fi
        done
        echo "Stripped $count VHDL file(s)."
    fi
}

################################################################################
# Format the given files in place or check their formatting.
# Globals:
#   None
# Arguments:
#   $1 - Run command, e.g. --check. Empty string formats files in place.
#   $2 - Name of the array variable containing files to format.
################################################################################
format_files() {
    local arg="$1"
    local -n files=$2

    # Format selected files.
    if [[ "${arg:-}" == "--check" ]]
    then
        clang-format --dry-run --Werror "${files[@]}"
    else
        local count=0
        for file in "${files[@]}"
        do
            before=$(md5sum "$file")
            clang-format -i "$file"
            after=$(md5sum "$file")
            if [[ "$before" != "$after" ]]
            then
                echo "Formatted: $file"
                ((++count))
            fi
        done
        echo "Formatted $count file(s)."
    fi
}

# Navigate to the root directory.
cd "$ROOT_DIR"

# Check if clang-format is installed.
check_clang_format

# Select files to format.
select_files FILES

# Nothing to do until this course has its own C/C++ files (the driver arrives lecture by lecture).
# Without this guard, clang-format would be invoked with no file arguments and block on stdin.
# Note this only skips the C/C++ pass: the VHDL pass below still runs, since hw/ has sources from
# L01 onwards while fw/ stays empty until L06.
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No C/C++ files to format yet."
else
    format_files "${1:-}" FILES
fi

# Select and process VHDL files.
select_vhdl_files VHDL_FILES

if [ "${#VHDL_FILES[@]}" -eq 0 ]; then
    echo "No VHDL files to check yet."
else
    strip_vhdl_whitespace "${1:-}" VHDL_FILES
fi
