#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Optional per-command timing helper for shell integration tests.
#
# Usage:
#   . "$(dirname "$0")/lib/timing.sh"
#   timed "label" command arg1 arg2
#
# Commands are always executed; timing output is emitted only when
# STACKALIGN_TIMING=1. The wrapped command's exit status is preserved.
timed() {
    local label="$1"
    shift
    local start end rc

    start=$(date +%s%N)
    if "$@"; then
        rc=0
    else
        rc=$?
    fi
    end=$(date +%s%N)

    if [[ "${STACKALIGN_TIMING:-0}" == "1" ]]; then
        printf '  [timing] %-45s %6dms\n' \
            "$label" "$(( (end-start)/1000000 ))" >&2
    fi

    return "$rc"
}
