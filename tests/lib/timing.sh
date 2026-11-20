#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# Optional per-command timing helper for shell integration tests.
#
# Usage:
#   . "$(dirname "$0")/lib/timing.sh"
#   timed "label" command arg1 arg2
#
# When timing is disabled, the command runs directly with no date subprocesses.
# If the platform clock is unavailable or lacks nanosecond support, the command
# still runs normally; instrumentation must never prevent the wrapped operation.
timed() {
    local label="$1"
    shift

    if [[ "${STACKALIGN_TIMING:-0}" != "1" ]]; then
        "$@"
        return $?
    fi

    local start end rc
    if ! start=$(date +%s%N 2>/dev/null) || [[ ! "$start" =~ ^[0-9]+$ ]]; then
        "$@"
        return $?
    fi

    if "$@"; then
        rc=0
    else
        rc=$?
    fi

    if end=$(date +%s%N 2>/dev/null) && [[ "$end" =~ ^[0-9]+$ ]]; then
        printf '  [timing] %-45s %6dms\n' \
            "$label" "$(( (end-start)/1000000 ))" >&2
    fi

    return "$rc"
}
