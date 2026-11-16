#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Regression tests for the optional timing helper.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/timing.sh
. "$ROOT/tests/lib/timing.sh"

tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT

: > "$tmp"
output="$(timed "disabled" printf 'stdout-preserved' 2>"$tmp")"
[[ "$output" == "stdout-preserved" ]]
[[ ! -s "$tmp" ]]

: > "$tmp"
if timed "failure status" bash -c 'exit 23' 2>"$tmp"; then
    echo "FAIL: timed hid the wrapped command's exit status" >&2
    exit 1
else
    rc=$?
fi
[[ "$rc" -eq 23 ]]

: > "$tmp"
output="$(STACKALIGN_TIMING=1 timed "enabled command" printf 'timed-output' 2>"$tmp")"
[[ "$output" == "timed-output" ]]
grep -Fq '[timing] enabled command' "$tmp"

# A platform without GNU nanosecond date support must still run the command.
date() { printf 'N'; }
: > "$tmp"
output="$(STACKALIGN_TIMING=1 timed "fallback clock" printf 'fallback-output' 2>"$tmp")"
unset -f date
[[ "$output" == "fallback-output" ]]
[[ ! -s "$tmp" ]]

: > "$tmp"
if STACKALIGN_TIMING=1 timed "enabled failure" bash -c 'exit 19' 2>"$tmp"; then
    echo "FAIL: timed hid an enabled command's exit status" >&2
    exit 1
else
    rc=$?
fi
[[ "$rc" -eq 19 ]]
grep -Fq '[timing] enabled failure' "$tmp"

echo "test_timing: disabled mode, output preservation, timing output, and exit-status propagation passed"
