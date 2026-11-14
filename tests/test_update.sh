#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_update.sh -- T35: good install, failed restart => downgrade to old NEVRA, exit 1.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/etc-pkg"; : > "$T/calls"
export CALLS="$T/calls" PATH="$T/bin:$PATH"

cat > "$T/bin/dnf" <<'F'
#!/usr/bin/env bash
echo "dnf $*" >> "$CALLS"
case "$*" in *downgrade*) exit "${FAKE_DNF_DOWNGRADE_RC:-0}" ;; esac
exit 0
F
cat > "$T/bin/rpm" <<'F'
#!/usr/bin/env bash
echo "OLD-1.0-1.x86_64"
F
cat > "$T/bin/systemctl" <<'F'
#!/usr/bin/env bash
echo "systemctl $*" >> "$CALLS"; exit 1
F
chmod +x "$T/bin/"*

log() { :; }
sa_history_snapshot() { echo "snapshot $*" >> "$CALLS"; echo SNAP42; }
sa_cache_get() { echo "$T/NEW.rpm"; }
sa_service_reload_safe() { echo "reload $*" >> "$CALLS"; systemctl restart "$1"; }
. "$ROOT/lib/update.sh"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2' want '$3')"; fail=1; fi; }

( sa_update_apply pkg NEW-2.0-1.x86_64 svc "$T/etc-pkg" ); rc=$?
check "exit 1 after rollback" "$rc" 1
grep -q "snapshot $T/etc-pkg pre-update-pkg" "$CALLS"; check "snapshot got one path + slug" "$?" 0
grep -q "reload svc SNAP42" "$CALLS"; check "reload got service+snapshot id" "$?" 0
grep -q "dnf -y downgrade OLD-1.0-1.x86_64" "$CALLS"; check "downgrade to old NEVRA" "$?" 0

: > "$CALLS"; export FAKE_DNF_DOWNGRADE_RC=1
( sa_update_apply pkg NEW-2.0-1.x86_64 svc "$T/etc-pkg" ); rc=$?
check "exit 99 when downgrade fails" "$rc" 99
unset FAKE_DNF_DOWNGRADE_RC

: > "$CALLS"
( sa_update_apply pkg NEW-2.0-1.x86_64 svc "$T/missing" ); rc=$?
check "missing snapshot path => refuse, exit 1" "$rc" 1
grep -q "dnf" "$CALLS"; check "no dnf call when refused" "$?" 1
exit "$fail"
