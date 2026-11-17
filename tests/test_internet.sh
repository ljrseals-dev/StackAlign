#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/lib/internet.sh"
pass=0 fail=0
ok(){ pass=$((pass+1)); echo "ok   - $1"; }
bad(){ fail=$((fail+1)); echo "FAIL - $1"; }
out=$(sa_internet_plan both cloudflare example.com 203.0.113.10 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"Access purpose: both"* ]] && [[ "$out" == *"no ports opened"* ]]; } && ok "combined public/private plan remains read-only" || bad "combined plan"
sa_internet_plan public cloudflare bad_domain 203.0.113.10 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "rejects malformed domain" || bad "domain validation"
sa_internet_plan public cloudflare example.com 999.1.1.1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "rejects out-of-range IPv4" || bad "IPv4 validation"
sa_internet_plan nonsense none "" "" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "rejects unknown access purpose" || bad "purpose validation"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
