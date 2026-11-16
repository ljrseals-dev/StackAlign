#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Run the canonical Makefile test target and report total wall-clock time.
# Test discovery and execution remain owned entirely by `make test`.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${STACKALIGN_TIMING:=1}"
export STACKALIGN_TIMING

start=$(date +%s%N)
rc=0
make test || rc=$?
end=$(date +%s%N)

printf '\n[time-tests] total wall clock: %dms (exit=%d)\n' \
    "$(( (end-start)/1000000 ))" "$rc" >&2

exit "$rc"
