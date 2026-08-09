#!/usr/bin/env bash
#
# Analyze, elaborate, and simulate the UART peripheral with GHDL.
#
# Every source file lives in one directory, hw/: the modules students write (including the
# peripheral top uart_top, built in L01), the instructor-provided testbenches (*_tb.vhd) that check
# them, and the provided sources students do not write: the register-map package uart_def, the reset
# synchronizer reset_sync, and the SPI transport (spi_slave, spi_reg_bridge). There are no per-lecture copies of anything.
#
# The peripheral is built up a module per lecture, so most of the tree is missing for most of the
# course. Each testbench declares the sources it needs and is skipped (not failed) until every
# one of them exists.
#
# Set CI_BUILD_ALL=1 to attempt every testbench regardless, e.g. to validate a complete reference
# set and catch a file that is present but does not analyze.
#
# Usage:
#   ci/build_vhdl.sh
set -euo pipefail

# Root directory.
ROOT_DIR="$(dirname "${BASH_SOURCE[0]}")/.."

# Navigate to the root directory.
cd "$ROOT_DIR"

# Source directory.
SRC_DIR="hw"

# Work library directory, kept out of the source tree so GHDL's artifacts don't clutter it.
WORK_DIR="$SRC_DIR/work"

# Wall-clock ceiling for a single simulation. Every testbench here finishes in well under a second,
# so this only ever fires on a genuine hang.
RUN_TIMEOUT_S="${RUN_TIMEOUT_S:-60}"

# Each testbench and the sources it needs, in analysis order (dependencies before dependents).
# uart_def is the shared package the register bank and several testbenches read, provided from the
# start, so it comes first where needed. spi_slave / spi_reg_bridge are the provided transport, also
# present from the start; every other module is a student deliverable, so a testbench gates on those
# existing.
TESTBENCHES=(
    "spi_slave_tb:uart_def spi_slave"
    "spi_reg_bridge_tb:uart_def spi_reg_bridge"
    "baud_gen_tb:baud_gen"
    "uart_tx_tb:uart_tx"
    "sync_tb:sync"
    "uart_rx_tb:uart_def uart_rx"
    "fifo_tb:uart_def fifo"
    "uart_regs_tb:uart_def fifo uart_regs"
    "uart_top_tb:uart_def reset_sync baud_gen sync fifo uart_tx uart_rx uart_regs spi_slave spi_reg_bridge uart_top"
)

# Every module, in dependency order. Analyzed on its own before any testbench runs, so a module
# written in an early lecture is syntax- and type-checked immediately rather than staying unproven
# until the testbench that finally exercises it can run.
MODULES="uart_def reset_sync baud_gen sync fifo uart_tx uart_rx uart_regs spi_slave spi_reg_bridge uart_top"

# Start from an empty library. Without this, units analyzed from a source that has since been
# renamed or deleted stay in work/ and a testbench can keep elaborating against a module the
# student no longer has, which reads as a pass it has not earned.
rm -rf "$WORK_DIR"

checked=0
for src in $MODULES; do
    if [ -f "$SRC_DIR/$src.vhd" ]; then
        mkdir -p "$WORK_DIR"
        ghdl -a --std=93 --workdir="$WORK_DIR" "$SRC_DIR/$src.vhd"
        echo "--> $src.vhd analyzes cleanly"
        checked=$((checked + 1))
    fi
done
if [ "$checked" -gt 0 ]; then
    echo
fi

ran=0
skipped=0

for entry in "${TESTBENCHES[@]}"; do
    tb="${entry%%:*}"
    sources="${entry#*:}"

    # Every *_tb.vhd is instructor-provided and ships from day one, so a missing testbench is a
    # real error rather than something to skip past: only the student-written modules below are
    # allowed to be absent.
    if [ ! -f "$SRC_DIR/$tb.vhd" ]; then
        echo "ERROR: $SRC_DIR/$tb.vhd is missing. Every testbench ships with the course; restore" >&2
        echo "       it from the repository rather than deleting it to get a green build." >&2
        exit 1
    fi

    # Skip until every module this testbench exercises has been written.
    missing=()
    for src in $sources; do
        if [ ! -f "$SRC_DIR/$src.vhd" ]; then
            missing+=("$src.vhd")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ] && [ "${CI_BUILD_ALL:-0}" != "1" ]; then
        echo "==> $tb (skipped: no ${missing[*]} yet)"
        skipped=$((skipped + 1))
        continue
    fi

    echo "==> $tb"
    mkdir -p "$WORK_DIR"

    # Analyze the modules in dependency order, then the testbench that drives them.
    for src in $sources; do
        ghdl -a --std=93 --workdir="$WORK_DIR" "$SRC_DIR/$src.vhd"
    done
    ghdl -a --std=93 --workdir="$WORK_DIR" "$SRC_DIR/$tb.vhd"

    # Elaborate and run. --assert-level=error makes a failed check stop the simulation with a
    # non-zero exit code, rather than printing and running on to a misleading "pass".
    #
    # The run is wrapped in `timeout` because a testbench that waits on a condition its DUT never
    # produces would otherwise hang forever with no output. Note that GHDL's own --stop-time is
    # not used here: it ends the simulation with exit code 0, turning a hang into a false pass,
    # whereas a timeout is a real failure and is reported as one.
    #
    # --ieee-asserts=disable-at-0 silences the numeric_std "metavalue detected" note that the
    # delta-0 evaluation of to_integer(unsigned(reg_addr)) emits before any driver has resolved.
    # It suppresses only IEEE library assertions at time 0; every assertion in these testbenches
    # is a user assertion and still fires normally.
    ghdl -e --std=93 --workdir="$WORK_DIR" -o "$WORK_DIR/$tb" "$tb"
    if ! timeout "$RUN_TIMEOUT_S" \
        ghdl -r --std=93 --workdir="$WORK_DIR" "$tb" --assert-level=error \
             --ieee-asserts=disable-at-0; then
        status=$?
        if [ "$status" -eq 124 ]; then
            echo "ERROR: $tb did not finish within ${RUN_TIMEOUT_S}s and was killed." >&2
            echo "       A testbench that hangs is usually waiting on a signal the module under" >&2
            echo "       test never drives; check that it leaves its reset/idle state at all." >&2
        fi
        exit 1
    fi

    ran=$((ran + 1))
done

echo
echo "$ran testbench(es) run, $skipped skipped."
