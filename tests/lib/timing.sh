#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Optional per-command timing helper for shell integration tests.
#
# Usage:
#   . "$(dirname "$0")/lib/timing.sh"
#   timed "label" command arg1 arg2
#
# When timing is disabled, the command runs directly with no date subprocesses.
# When enabled, the wrapped command's output and exit status are preserved.
timed() {
    local label="$1"
    shift

    if [[ "${STACKALIGN_TIMING:-0}" != "1" ]]; then
        "$@"
        return $?
    fi

    local start end rc
    start=$(date +%s%N) || return
    if "$@"; then
        rc=0
    else
        rc=$?
    fi
    end=$(date +%s%N) || return

    printf '  [timing] %-45s %6dms\n' \
        "$label" "$(( (end-start)/1000000 ))" >&2

    return "$rc"
}
