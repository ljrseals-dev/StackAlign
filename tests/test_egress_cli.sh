#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_egress_cli.sh -- CLI routing/plan tests; never invokes nft.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '%s\n' "203.0.113.10 tcp 443" > "$T/allow"
out="$("$ROOT/bin/stackalign" help egress 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [[ "$out" == *"egress"* ]] || { echo "FAIL egress help"; exit 1; }
out="$("$ROOT/bin/stackalign" egress plan "$T/allow" 9.9.9.9 none 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [[ "$out" == *"policy drop"* ]] && [[ "$out" == *"plan only"* ]] || { echo "FAIL egress plan"; exit 1; }
out="$("$ROOT/bin/stackalign" egress apply "$T/allow" 9.9.9.9 none 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [[ "$out" == *"plan only"* ]] || { echo "FAIL apply defaults to plan"; exit 1; }
"$ROOT/bin/stackalign" egress remove >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] || { echo "FAIL remove requires explicit --apply"; exit 1; }
echo "egress CLI tests: ok"
