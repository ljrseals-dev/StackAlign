#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/lib/config.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }

cat > "$T/good.conf" <<'EOF'
# comment
[meta]
config_version = 1

[update]
check = weekly
window = "Sun 03:00"
  [server]
  role=primary
EOF
sa_config_load "$T/good.conf" 2>/dev/null; rc=$?
[ $rc -eq 0 ] && ok "valid file loads" || bad "valid file loads"
[ "$(sa_config_get update.check)" = weekly ] && ok "get value" || bad "get value"
[ "$(sa_config_get update.window)" = "Sun 03:00" ] && ok "quoted value unquoted" || bad "quoted value unquoted"
[ "$(sa_config_get server.role)" = primary ] && ok "indent and no-space '=' ok" || bad "indent and no-space '=' ok"
[ "$(sa_config_get nope.x fallback)" = fallback ] && ok "default on missing" || bad "default on missing"
sa_config_get nope.x >/dev/null; [ $? -ne 0 ] && ok "missing without default fails" || bad "missing without default fails"

# version gate
printf '[meta]\nconfig_version = 2\n' > "$T/v2.conf"
sa_config_load "$T/v2.conf" 2>/dev/null; [ $? -ne 0 ] && ok "unknown version refused" || bad "unknown version refused"
printf '[server]\nrole = primary\n' > "$T/nometa.conf"
sa_config_load "$T/nometa.conf" 2>/dev/null; [ $? -ne 0 ] && ok "missing [meta] refused" || bad "missing [meta] refused"

# duplicates
printf '[meta]\nconfig_version = 1\n[a]\nk = 1\nk = 2\n' > "$T/dup.conf"
sa_config_load "$T/dup.conf" 2>/dev/null; [ $? -ne 0 ] && ok "same-section duplicate is hard error" || bad "same-section duplicate is hard error"
printf '[meta]\nconfig_version = 1\n[a]\nk = 1\n[b]\nk = 2\n' > "$T/dupx.conf"
sa_config_load "$T/dupx.conf" 2>/dev/null; [ $? -eq 0 ] && ok "same key in different sections ok" || bad "same key in different sections ok"
printf '[meta]\nconfig_version = 1\nallow_override = 1\n[a]\nk = 1\nk = 2\n' > "$T/ovr.conf"
sa_config_load "$T/ovr.conf" 2>"$T/ovr.err"; rc=$?
w=$(cat "$T/ovr.err")
{ [ $rc -eq 0 ] && [ "$(sa_config_get a.k)" = 2 ] && [[ $w == *WARNING* ]]; } && ok "allow_override: last wins + warning" || bad "allow_override: last wins + warning"
# allow_override declared AFTER the duplicates still counts
printf '[a]\nk = 1\nk = 2\n[meta]\nconfig_version = 1\nallow_override = 1\n' > "$T/late.conf"
sa_config_load "$T/late.conf" 2>/dev/null; [ $? -eq 0 ] && ok "allow_override order-independent" || bad "allow_override order-independent"

# malformed
printf '[meta]\nconfig_version = 1\nthis is garbage\n' > "$T/junk.conf"
sa_config_load "$T/junk.conf" 2>/dev/null; [ $? -ne 0 ] && ok "garbage line refused" || bad "garbage line refused"
printf 'k = 1\n[meta]\nconfig_version = 1\n' > "$T/nosec.conf"
sa_config_load "$T/nosec.conf" 2>/dev/null; [ $? -ne 0 ] && ok "key before any section refused" || bad "key before any section refused"

# never evaluates values
printf '[meta]\nconfig_version = 1\n[a]\nk = $(touch %s/PWNED)\n' "$T" > "$T/inj.conf"
sa_config_load "$T/inj.conf" 2>/dev/null
{ [ ! -e "$T/PWNED" ] && [ "$(sa_config_get a.k)" = "\$(touch $T/PWNED)" ]; } && ok "values are data, not evaluated" || bad "values are data, not evaluated"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
