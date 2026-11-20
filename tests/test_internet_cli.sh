#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/bin/stackalign"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/config"
pass=0 fail=0
ok(){ pass=$((pass+1)); echo "ok   - $1"; }
bad(){ fail=$((fail+1)); echo "FAIL - $1"; }
out=$(bash "$CLI" internet apply 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && [[ "$out" == *"no changes made"* ]]; } && ok "internet apply fails closed" || bad "apply gate"
out=$(bash "$CLI" internet setup </dev/null 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && [[ "$out" == *"interactive terminal"* ]]; } && ok "setup refuses non-interactive execution" || bad "noninteractive guard"
out=$(bash "$CLI" internet plan 2>&1); rc=$?
{ [ "$rc" -ne 0 ] && [[ "$out" == *"saved setup is missing"* ]]; } && ok "plan requires saved preferences" || bad "missing config"
out=$(bash "$CLI" internet unknown 2>&1); rc=$?
[ "$rc" -eq 64 ] && ok "unknown subcommand rejected" || bad "unknown subcommand"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
