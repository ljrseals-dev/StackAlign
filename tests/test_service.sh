#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Uses fake systemctl/nginx/mysqladmin/php-fpm in a private PATH. No real service is touched.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export SA_HISTORY_ROOT="$T/hist" SA_SECRETS_DIR="$T/secrets"
export FAKE_LOG="$T/calls.log" FAKE_STATE="$T/state" FAKE_CONF="$T/nginx.conf"
mkdir -p "$T/bin" "$FAKE_STATE"

cat > "$T/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$FAKE_LOG"
case $1 in is-active) [ -e "$FAKE_STATE/$3.active" ] ;; *) exit 0 ;; esac
EOF
cat > "$T/bin/nginx" <<'EOF'
#!/usr/bin/env bash
[ -e "$FAKE_STATE/always_fail" ] && exit 1
! grep -q BAD "$FAKE_CONF"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/mysqladmin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/php-fpm"
chmod +x "$T/bin"/*
export PATH="$T/bin:$PATH"

source "$ROOT/lib/history.sh"; source "$ROOT/lib/service.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }
reset() { : > "$FAKE_LOG"; rm -f "$FAKE_STATE"/*; touch "$FAKE_STATE/nginx.active"; printf 'good\n' > "$FAKE_CONF"; }

# health dispatch
reset; sa_service_health nginx && sa_service_health php-fpm && sa_service_health mariadb && ok "health dispatch ok" || bad "health dispatch ok"
sa_service_health bogus 2>/dev/null; [ $? -eq 64 ] && ok "unknown service -> 64" || bad "unknown service -> 64"

# healthy path
reset; id=$(sa_history_snapshot "$FAKE_CONF" t)
sa_service_reload_safe nginx "$id"; rc=$?
{ [ $rc -eq 0 ] && grep -q 'systemctl reload nginx' "$FAKE_LOG"; } && ok "healthy: reloads, returns 0" || bad "healthy: reloads, returns 0"

# bad config: pre-health fails -> no reload, rollback, restart, recovered -> rc 1
reset; id=$(sa_history_snapshot "$FAKE_CONF" t); printf 'BAD\n' > "$FAKE_CONF"
sa_service_reload_safe nginx "$id" 2>/dev/null; rc=$?
{ [ $rc -eq 1 ] && [ "$(cat "$FAKE_CONF")" = good ] && grep -q 'systemctl restart nginx' "$FAKE_LOG" && ! grep -q 'systemctl reload' "$FAKE_LOG"; } \
  && ok "bad config: rolled back, restarted, rc=1, never reloaded" || bad "bad config: rolled back, restarted, rc=1, never reloaded"

# still unhealthy after rollback -> exit 99 + CRITICAL
reset; id=$(sa_history_snapshot "$FAKE_CONF" t); touch "$FAKE_STATE/always_fail"
msg=$( ( sa_service_reload_safe nginx "$id" ) 2>&1 ); rc=$?
{ [ $rc -eq 99 ] && [[ $msg == *"CRITICAL: manual intervention required"* ]]; } && ok "persistent failure: exit 99 + CRITICAL" || bad "persistent failure: exit 99 + CRITICAL (rc=$rc)"

# fail closed without snapshot id; no systemctl calls
reset; sa_service_reload_safe nginx "" 2>/dev/null; rc=$?
{ [ $rc -ne 0 ] && [ ! -s "$FAKE_LOG" ]; } && ok "no snapshot id: refused, nothing run" || bad "no snapshot id: refused, nothing run"

# inactive is a no-op; FORCE reloads
reset; rm "$FAKE_STATE/nginx.active"; id=$(sa_history_snapshot "$FAKE_CONF" t)
sa_service_reload_safe nginx "$id" >/dev/null; rc=$?
{ [ $rc -eq 0 ] && ! grep -q 'systemctl reload' "$FAKE_LOG"; } && ok "inactive: reload skipped" || bad "inactive: reload skipped"
SA_SERVICE_FORCE=1 sa_service_reload nginx >/dev/null
grep -q 'systemctl reload nginx' "$FAKE_LOG" && ok "SA_SERVICE_FORCE=1 reloads inactive" || bad "SA_SERVICE_FORCE=1 reloads inactive"

# plan mode touches nothing
reset; SA_MODE=plan sa_service_reload_safe nginx "" >/dev/null; rc=$?
{ [ $rc -eq 0 ] && [ ! -s "$FAKE_LOG" ]; } && ok "plan mode: no actions" || bad "plan mode: no actions"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
