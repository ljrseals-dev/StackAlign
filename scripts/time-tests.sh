#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# Run the canonical Makefile test target and report total wall-clock time.
# Test discovery and execution remain owned entirely by `make test`.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${STACKALIGN_TIMING:=1}"
export STACKALIGN_TIMING

if start=$(date +%s%N 2>/dev/null) && [[ "$start" =~ ^[0-9]+$ ]]; then
    clock_mode=nanoseconds
else
    # Bash SECONDS is a portable, coarse fallback when GNU date is unavailable.
    start=$SECONDS
    clock_mode=seconds
fi

rc=0
make test || rc=$?

if [[ "$clock_mode" == "nanoseconds" ]]; then
    if end=$(date +%s%N 2>/dev/null) && [[ "$end" =~ ^[0-9]+$ ]]; then
        elapsed_ms=$(( (end-start)/1000000 ))
    else
        elapsed_ms=$(( (SECONDS-start)*1000 ))
        clock_mode=seconds-fallback
    fi
else
    elapsed_ms=$(( (SECONDS-start)*1000 ))
fi

printf '\n[time-tests] total wall clock: %dms (%s clock, exit=%d)\n' \
    "$elapsed_ms" "$clock_mode" "$rc" >&2

exit "$rc"
