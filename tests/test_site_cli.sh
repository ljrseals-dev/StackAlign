#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# CLI routing must preserve gated site lifecycle and reject malformed domains.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

set +e
bash "$ROOT/bin/stackalign" site add example.com >"$TMP/out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -q 'BLOCKED' "$TMP/out"

set +e
bash "$ROOT/bin/stackalign" site add 'example.com;id' >"$TMP/invalid" 2>&1
bad_rc=$?
set -e
[ "$bad_rc" -eq 64 ]
! grep -q 'BLOCKED' "$TMP/invalid"

echo 'site CLI tests: PASS'
