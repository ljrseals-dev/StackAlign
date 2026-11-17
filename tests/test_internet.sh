#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/config"
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

mkdir -p "$XDG_CONFIG_HOME/stackalign"
chmod 700 "$XDG_CONFIG_HOME/stackalign"
printf 'version=1\\npurpose=both\\nprovider=tailscale\\ndomain=example.com\\nserver_ipv4=203.0.113.10\\n' > "$XDG_CONFIG_HOME/stackalign/internet.conf"
chmod 600 "$XDG_CONFIG_HOME/stackalign/internet.conf"
out=$(sa_internet_show_saved_plan 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"Access purpose: both"* ]]; } && ok "loads valid owner-only saved config" || bad "valid saved config"
printf 'version=1\\npurpose=both\\npurpose=private\\nprovider=tailscale\\n' > "$XDG_CONFIG_HOME/stackalign/internet.conf"
chmod 600 "$XDG_CONFIG_HOME/stackalign/internet.conf"
sa_internet_show_saved_plan >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "rejects duplicate config keys" || bad "duplicate config key"
printf 'version=1\\npurpose=both\\nprovider=tailscale\\n' > "$XDG_CONFIG_HOME/stackalign/internet-real"
chmod 600 "$XDG_CONFIG_HOME/stackalign/internet-real"
ln -sf internet-real "$XDG_CONFIG_HOME/stackalign/internet.conf"
sa_internet_show_saved_plan >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "rejects symlinked config file" || bad "symlink config"
rm -f "$XDG_CONFIG_HOME/stackalign/internet.conf"
printf 'version=1\\npurpose=both\\nprovider=tailscale\\n' > "$XDG_CONFIG_HOME/stackalign/internet.conf"
chmod 644 "$XDG_CONFIG_HOME/stackalign/internet.conf"
sa_internet_show_saved_plan >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "rejects group/world-readable config" || bad "config permissions"
XDG_CONFIG_HOME=relative sa_internet_config_path >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "rejects relative XDG_CONFIG_HOME" || bad "relative XDG path"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
