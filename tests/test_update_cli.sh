#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_update_cli.sh -- CLI-level proof that exit codes 1 and 99 reach the shell.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

TARGET="nginx-1.31.0-1.el9.x86_64"
OLD="nginx-1.30.6-1.el9.x86_64"
export FAKE_TARGET="$TARGET" FAKE_OLD="$OLD"

mkdir -p "$work/etc-nginx"; echo cfg > "$work/etc-nginx/nginx.conf"   # snapshot target

cat > "$work/dnf" <<'FAKE'
#!/usr/bin/env bash
echo "dnf $*" >> "$DNF_LOG"
case "$*" in
    *downgrade*) exit "${DNF_DOWNGRADE_RC:-0}" ;;
esac
exit 0
FAKE

cat > "$work/systemctl" <<'FAKE'
#!/usr/bin/env bash
# Queries succeed; EVERY state-changing action fails, whether the real helper
# uses restart, reload, reload-or-restart, try-restart, or start.
case "$*" in
    *is-active*|*is-enabled*|*status*|*show*|*cat*) exit 0 ;;
esac
exit 1
FAKE

# ORDER MATTERS: -qp (package file) before plain -q.
cat > "$work/rpm" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
    *"-qp"*) printf '%s' "$FAKE_TARGET"; exit 0 ;;
    *"-q "*) printf '%s' "$FAKE_OLD"; exit 0 ;;
esac
exit 0   # --checksig etc.
FAKE
# Fake nginx so any `nginx -t` inside the reload path is deterministic (host-independent).
cat > "$work/nginx" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
chmod +x "$work/dnf" "$work/systemctl" "$work/rpm" "$work/nginx"

export PATH="$work:$PATH"
export DNF_LOG="$work/dnf.log"
export SA_RPM_CACHE="$work/rpm-cache"
export SA_HISTORY_ROOT="$work/history"      # real variable used by lib/history.sh
mkdir -p "$SA_RPM_CACHE" "$SA_HISTORY_ROOT"
: > "$SA_RPM_CACHE/$TARGET.rpm"             # pre-seed so no real download is needed

fail=0
run_case() {
    local name="$1" downgrade_rc="$2" expected_rc="$3" rc=0
    : > "$DNF_LOG"
    DNF_DOWNGRADE_RC="$downgrade_rc" \
        bash "$root/bin/stackalign" update apply nginx "$TARGET" nginx "$work/etc-nginx" \
        >/dev/null 2>&1 || rc=$?

    if [ "$rc" -ne "$expected_rc" ]; then
        echo "FAIL $name: expected exit $expected_rc, got $rc"; cat "$DNF_LOG"; fail=1; return
    fi
    grep -q "dnf -y install" "$DNF_LOG" || { echo "FAIL $name: install not reached"; fail=1; return; }
    grep -q "dnf -y downgrade $OLD" "$DNF_LOG" || { echo "FAIL $name: no downgrade to $OLD"; cat "$DNF_LOG"; fail=1; return; }
    echo "PASS $name"
}

run_case "restart fails, downgrade ok -> exit 1"     0 1
run_case "restart fails, downgrade fails -> exit 99" 1 99

# Wrong argument count must not touch dnf.
: > "$DNF_LOG"; rc=0
bash "$root/bin/stackalign" update apply nginx "$TARGET" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 64 ] && [ ! -s "$DNF_LOG" ]; then echo "PASS bad args -> 64, no dnf"; else echo "FAIL bad args (rc=$rc)"; fail=1; fi

exit "$fail"
