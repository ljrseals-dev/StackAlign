#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_update.sh -- sa_update_apply against the REAL service.sh contract
# (reload_safe may `exit 99`; downgrade must be followed by restart + health).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/etc-pkg"; : > "$T/calls"; echo OLD-1.0-1.x86_64 > "$T/installed"
export CALLS="$T/calls" PATH="$T/bin:$PATH"

cat > "$T/bin/dnf" <<'F'
#!/usr/bin/env bash
echo "dnf $*" >> "$CALLS"
case "$*" in
  *downgrade*) [ "${FAKE_DOWNGRADE_RC:-0}" = 0 ] && echo OLD-1.0-1.x86_64 > "$STATE"; exit "${FAKE_DOWNGRADE_RC:-0}" ;;
  *install*)   [ "${FAKE_INSTALL_RC:-0}" = 0 ] && echo NEW-2.0-1.x86_64 > "$STATE"
               [ "${FAKE_INSTALL_PARTIAL:-0}" = 1 ] && echo NEW-2.0-1.x86_64 > "$STATE"
               exit "${FAKE_INSTALL_RC:-0}" ;;
esac
exit 0
F
cat > "$T/bin/rpm" <<'F'
#!/usr/bin/env bash
cat "$STATE"
F
chmod +x "$T/bin/"*
export STATE="$T/installed"

log() { :; }
sa_history_snapshot() { echo "snapshot $*" >> "$CALLS"; echo SNAP42; }
sa_cache_get() { echo "$T/NEW.rpm"; }
HC="$T/healthcount"
sa_service_health() {
    echo "health $*" >> "$CALLS"
    local n; n=$(( $(cat "$HC" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$HC"
    [ "${FAKE_HEALTH_FAIL_FROM:-0}" -gt 0 ] && [ "$n" -ge "$FAKE_HEALTH_FAIL_FROM" ] && return 1
    [ "$1" = bogus ] && return 64
    return 0
}
sa_service_restart() { echo "restart $*" >> "$CALLS"; return "${FAKE_RESTART_RC:-0}"; }
sa_service_reload_safe() {
    echo "reload $*" >> "$CALLS"
    [ "${FAKE_RELOAD_EXIT99:-0}" = 1 ] && exit 99      # the real helper does this
    return "${FAKE_RELOAD_RC:-0}"
}
. "$ROOT/lib/update.sh"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2' want '$3')"; fail=1; fi; }
reset() { : > "$CALLS"; : > "$HC"; echo OLD-1.0-1.x86_64 > "$STATE"; unset FAKE_RELOAD_RC FAKE_RELOAD_EXIT99 FAKE_DOWNGRADE_RC FAKE_INSTALL_RC FAKE_INSTALL_PARTIAL FAKE_HEALTH_FAIL_FROM FAKE_RESTART_RC; }
has() { grep -q -- "$1" "$CALLS"; }
run() { ( sa_update_apply pkg NEW-2.0-1.x86_64 svc "$T/etc-pkg" ) >/dev/null 2>&1; }

reset; run; check "success => 0" "$?" 0
has "dnf -y downgrade"; check "no downgrade on success" "$?" 1
has "snapshot $T/etc-pkg pre-update-pkg"; check "snapshot: one path + slug" "$?" 0
has "reload svc SNAP42"; check "reload got service + snapshot id" "$?" 0

reset; export FAKE_RELOAD_RC=1; run; check "reload fails, downgrade ok => 1" "$?" 1
has "dnf -y downgrade OLD-1.0-1.x86_64"; check "downgrade to old NEVRA" "$?" 0
has "restart svc"; check "restart after downgrade" "$?" 0

reset; export FAKE_RELOAD_EXIT99=1; run; check "reload_safe exit 99 is caught => rollback => 1" "$?" 1
has "dnf -y downgrade OLD-1.0-1.x86_64"; check "downgrade still attempted after exit 99" "$?" 0

reset; export FAKE_RELOAD_RC=1 FAKE_DOWNGRADE_RC=1; run; check "downgrade fails => 99" "$?" 99

reset; export FAKE_RELOAD_RC=1 FAKE_HEALTH_FAIL_FROM=2; run; check "unhealthy after downgrade => 99" "$?" 99
reset; export FAKE_RELOAD_RC=1 FAKE_RESTART_RC=1; run; check "restart fails after downgrade => 99" "$?" 99

reset; export FAKE_HEALTH_FAIL_FROM=1; run; check "unhealthy before update => refuse (1)" "$?" 1
has "dnf"; check "no dnf when unhealthy" "$?" 1

reset; ( sa_update_apply pkg NEW-2.0-1.x86_64 bogus "$T/etc-pkg" ) >/dev/null 2>&1; check "unknown service refused" "$?" 1
has "dnf"; check "no dnf for unknown service" "$?" 1

reset; export FAKE_INSTALL_RC=1; run; check "install fails, unchanged => 1" "$?" 1
has "downgrade"; check "no downgrade when nothing changed" "$?" 1
reset; export FAKE_INSTALL_RC=1 FAKE_INSTALL_PARTIAL=1; run; check "install fails part-way => rollback => 1" "$?" 1
has "dnf -y downgrade OLD-1.0-1.x86_64"; check "downgrade after partial install" "$?" 0

reset; ( sa_update_apply pkg NEW-2.0-1.x86_64 svc "$T/missing" ) >/dev/null 2>&1; check "missing snapshot path => 1" "$?" 1
has "dnf"; check "no dnf when refused" "$?" 1

reset; ( sa_update_apply 'lib++' NEW-2.0-1.x86_64 svc "$T/etc-pkg" ) >/dev/null 2>&1
has "snapshot $T/etc-pkg pre-update-lib__"; check "slug sanitised (lib++ -> lib__)" "$?" 0
exit "$fail"
