#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/bin/stackalign"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok(){ pass=$((pass+1)); echo "ok   - $1"; }
bad(){ fail=$((fail+1)); echo "FAIL - $1"; }
out=$(bash "$CLI" hosting plan apache 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"Mode: apache"* ]] && [[ "$out" == *"Apply: BLOCKED"* ]]; } && ok "CLI exposes Apache plan and explicit apply gate" || bad "Apache CLI plan"
out=$(bash "$CLI" hosting plan hybrid 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"127.0.0.1:8081"* ]]; } && ok "CLI exposes private hybrid upstream plan" || bad "hybrid CLI plan"
bash "$CLI" hosting doctor nginx >/dev/null 2>&1; rc=$?
[ "$rc" -ne 64 ] && ok "doctor accepts explicit nginx mode" || bad "doctor mode argument"
bash "$CLI" hosting setup </dev/null >"$T/out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q "interactive terminal" "$T/out" && ok "setup refuses non-interactive execution safely" || bad "setup non-interactive guard"
bash "$CLI" hosting apply >"$T/out" 2>&1; rc=$?
{ [ "$rc" -eq 2 ] && grep -q "no changes made" "$T/out"; } && ok "CLI refuses apply without changing host" || bad "apply fail-closed"
bash "$CLI" hosting plan unknown >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "CLI rejects unknown hosting mode" || bad "unknown mode"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
