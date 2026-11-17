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


# Failed loads must not leave values from the failed file or prior successful load.
sa_config_load "$T/good.conf" 2>/dev/null
printf '[meta]\nconfig_version = 1\n[broken]\nnot-an-assignment\n' > "$T/partial.conf"
sa_config_load "$T/partial.conf" 2>/dev/null
{ [ $? -ne 0 ] && [ "${#SA_CONF[@]}" -eq 0 ]; } && ok "parse failure clears partial configuration" || bad "parse failure clears partial configuration"
sa_config_load "$T/good.conf" 2>/dev/null
sa_config_load "$T/dup.conf" 2>/dev/null
{ [ $? -ne 0 ] && [ "${#SA_CONF[@]}" -eq 0 ]; } && ok "duplicate-key failure clears configuration" || bad "duplicate-key failure clears configuration"
sa_config_load "$T/good.conf" 2>/dev/null
sa_config_load "$T/missing.conf" 2>/dev/null
{ [ $? -ne 0 ] && [ "${#SA_CONF[@]}" -eq 0 ]; } && ok "missing-file failure clears prior configuration" || bad "missing-file failure clears prior configuration"
sa_config_load 2>/dev/null
{ [ $? -ne 0 ] && [ "${#SA_CONF[@]}" -eq 0 ]; } && ok "missing argument rejected without stale values" || bad "missing argument rejected without stale values"


# Strict schema v1 validation is opt-in; generic INI parsing remains independent.
cat > "$T/schema-good.conf" <<'EOF'
[meta]
config_version = 1
allow_override = 0
[server]
role = slave_web
tenant_mode = pool
sites_dir = /srv/sites
[php]
workload = wordpress
[redis.sessions]
enabled = true
maxmemory_mib = 32
maxmemory_policy = noeviction
port = 6379
[site.alpha]
domain = alpha.example.test
user = site_alpha
pool = site_alpha
isolation = pool
memory_max_mib = 256
cpu_quota_pct = 100
egress = loopback_db_only
open_basedir_extra = /srv/shared
php_version = 8.3
EOF
sa_config_load "$T/schema-good.conf" 2>/dev/null && sa_config_validate 2>/dev/null && ok "schema v1 accepts valid tenant config" || bad "schema v1 accepts valid tenant config"
printf '[meta]\nconfig_version=1\n[server]\nrole=slave_web\nunknown=1\n' > "$T/schema-unknown.conf"
sa_config_load "$T/schema-unknown.conf" 2>/dev/null && sa_config_validate 2>/dev/null
[ $? -ne 0 ] && ok "schema rejects unknown keys" || bad "schema rejects unknown keys"
printf '[meta]\nconfig_version=1\n[redis.sessions]\nport=70000\n' > "$T/schema-port.conf"
sa_config_load "$T/schema-port.conf" 2>/dev/null && sa_config_validate 2>/dev/null
[ $? -ne 0 ] && ok "schema rejects out-of-range Redis ports" || bad "schema rejects out-of-range Redis ports"
printf '[meta]\nconfig_version=1\n[site.alpha]\ndomain=bad..example\nuser=site_alpha\npool=site_alpha\nisolation=pool\n' > "$T/schema-domain.conf"
sa_config_load "$T/schema-domain.conf" 2>/dev/null && sa_config_validate 2>/dev/null
[ $? -ne 0 ] && ok "schema rejects malformed tenant domains" || bad "schema rejects malformed tenant domains"
cat > "$T/schema-multi.conf" <<'EOF'
[meta]
config_version = 1
[server]
tenant_mode = free_for_all
[site.alpha]
domain = alpha.example.test
user = site_alpha
pool = site_alpha
isolation = free_for_all
[site.beta]
domain = beta.example.test
user = site_beta
pool = site_beta
isolation = free_for_all
EOF
sa_config_load "$T/schema-multi.conf" 2>/dev/null && sa_config_validate 2>/dev/null
[ $? -ne 0 ] && ok "schema rejects multiple sites in free_for_all mode" || bad "schema rejects multiple sites in free_for_all mode"

cat > "$T/schema-mode-mismatch.conf" <<'EOF'
[meta]
config_version = 1
[server]
tenant_mode = pool
[site.alpha]
domain = alpha.example.test
user = site_alpha
pool = site_alpha
isolation = free_for_all
EOF
sa_config_load "$T/schema-mode-mismatch.conf" 2>/dev/null && sa_config_validate 2>/dev/null
[ $? -ne 0 ] && ok "schema rejects tenant isolation mode mismatch" || bad "schema rejects tenant isolation mode mismatch"

sa_config_load "$T/good.conf" 2>/dev/null
sa_config_validate 2>/dev/null
[ $? -ne 0 ] && ok "generic parser does not imply schema validity" || bad "generic parser does not imply schema validity"


# Public CLI validates without writing or mutating the source file.
"$ROOT/bin/stackalign" config validate "$T/schema-good.conf" >/dev/null 2>&1
[ $? -eq 0 ] && ok "CLI validates a schema v1 file" || bad "CLI validates a schema v1 file"
"$ROOT/bin/stackalign" config validate "$T/schema-unknown.conf" >/dev/null 2>&1
[ $? -ne 0 ] && ok "CLI rejects unknown schema keys" || bad "CLI rejects unknown schema keys"


printf '[meta]\nconfig_version=1\n[redis.sessions]\nport=99999999999999999999\n' > "$T/schema-huge-number.conf"
sa_config_load "$T/schema-huge-number.conf" 2>/dev/null && sa_config_validate 2>/dev/null
[ $? -ne 0 ] && ok "schema rejects oversized numeric input" || bad "schema rejects oversized numeric input"
cat > "$T/schema-duplicate-user.conf" <<'EOF'
[meta]
config_version = 1
[server]
tenant_mode = pool
[site.alpha]
domain = alpha.example.test
user = shared_user
pool = alpha_pool
isolation = pool
[site.beta]
domain = beta.example.test
user = shared_user
pool = beta_pool
isolation = pool
EOF
sa_config_load "$T/schema-duplicate-user.conf" 2>/dev/null && sa_config_validate 2>/dev/null
[ $? -ne 0 ] && ok "schema rejects duplicate tenant Unix identities" || bad "schema rejects duplicate tenant Unix identities"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
