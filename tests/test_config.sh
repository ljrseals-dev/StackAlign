#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/lib/config.sh"
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }

cat > "$T/good.conf" <<'EOF'
# comment
[meta]
config_version = 1
allow_override = 0

[security]
password_mode = "machine"
EOF
sa_config_load "$T/good.conf" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "valid allowlisted config loads" || bad "valid config loads"
[ "$(sa_config_get security.password_mode)" = machine ] && ok "security password mode parsed" || bad "password mode parsed"
[ "$(sa_config_get security.missing fallback)" = fallback ] && ok "default on missing" || bad "default on missing"
sa_config_get security.missing >/dev/null 2>&1; [ $? -ne 0 ] && ok "missing without default fails" || bad "missing without default fails"

printf '[meta]\nconfig_version = 2\n' > "$T/v2.conf"
sa_config_load "$T/v2.conf" 2>/dev/null; [ $? -ne 0 ] && ok "unknown version refused" || bad "unknown version refused"
printf '[security]\npassword_mode = machine\n' > "$T/nometa.conf"
sa_config_load "$T/nometa.conf" 2>/dev/null; [ $? -ne 0 ] && ok "missing [meta] refused" || bad "missing [meta] refused"

printf '[meta]\nconfig_version = 1\n[security]\npassword_mode = machine\npassword_mode = human-legacy\n' > "$T/dup.conf"
sa_config_load "$T/dup.conf" 2>/dev/null; [ $? -ne 0 ] && ok "same-section duplicate is hard error" || bad "duplicate is hard error"
printf '[meta]\nconfig_version = 1\nallow_override = 1\n[security]\npassword_mode = machine\npassword_mode = human-legacy\n' > "$T/ovr.conf"
sa_config_load "$T/ovr.conf" 2>"$T/ovr.err"; rc=$?
w=$(cat "$T/ovr.err")
{ [ "$rc" -eq 0 ] && [ "$(sa_config_get security.password_mode)" = human-legacy ] && [[ $w == *WARNING* ]]; } && ok "allow_override: last wins + warning" || bad "allow_override behavior"
printf '[security]\npassword_mode = machine\npassword_mode = human-legacy\n[meta]\nconfig_version = 1\nallow_override = 1\n' > "$T/late.conf"
sa_config_load "$T/late.conf" 2>/dev/null; [ $? -eq 0 ] && ok "allow_override order-independent" || bad "allow_override order-independent"

printf '[meta]\nconfig_version = 1\n[update]\ncheck = weekly\n' > "$T/unknown.conf"
sa_config_load "$T/unknown.conf" 2>/dev/null; [ $? -ne 0 ] && ok "unknown section/key rejected" || bad "unknown key rejected"
printf '[meta]\nconfig_version = 1\n[security]\npassword_mode = unsafe\n' > "$T/type.conf"
sa_config_load "$T/type.conf" 2>/dev/null; [ $? -ne 0 ] && ok "invalid enum rejected" || bad "invalid enum rejected"
printf '[meta]\nconfig_version = 1\nallow_override = yes\n' > "$T/bool.conf"
sa_config_load "$T/bool.conf" 2>/dev/null; [ $? -ne 0 ] && ok "invalid boolean rejected" || bad "invalid boolean rejected"

printf '[meta]\nconfig_version = 1\n[security]\npassword_mode = $(touch %s/PWNED)\n' "$T" > "$T/inj.conf"
sa_config_load "$T/inj.conf" 2>/dev/null
{ [ $? -ne 0 ] && [ ! -e "$T/PWNED" ]; } && ok "shell syntax in config rejected as data" || bad "config value not executed"

printf '[meta]\nconfig_version = 1\n[broken]\nnot-an-assignment\n' > "$T/partial.conf"
sa_config_load "$T/good.conf" 2>/dev/null
sa_config_load "$T/partial.conf" 2>/dev/null
{ [ $? -ne 0 ] && [ "${#SA_CONF[@]}" -eq 0 ]; } && ok "parse failure clears partial configuration" || bad "parse failure clears partial configuration"
sa_config_load "$T/good.conf" 2>/dev/null
sa_config_load "$T/dup.conf" 2>/dev/null
{ [ $? -ne 0 ] && [ "${#SA_CONF[@]}" -eq 0 ]; } && ok "duplicate failure clears configuration" || bad "duplicate failure clears configuration"
sa_config_load "$T/good.conf" 2>/dev/null
sa_config_load "$T/missing.conf" 2>/dev/null
{ [ $? -ne 0 ] && [ "${#SA_CONF[@]}" -eq 0 ]; } && ok "missing-file failure clears prior configuration" || bad "missing-file failure clears prior configuration"
sa_config_load 2>/dev/null
{ [ $? -ne 0 ] && [ "${#SA_CONF[@]}" -eq 0 ]; } && ok "missing argument rejected" || bad "missing argument rejected"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
