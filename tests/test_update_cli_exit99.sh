#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_update_cli_exit99.sh -- coverage for the fatal service-reload path.
#
# main already has the correct behavior; this closes a coverage gap.
#
# Contract exercised:
#   * lib/update.sh captures sa_service_reload_safe in a subshell:
#         ( sa_service_reload_safe "$svc" "$snap" ); rc=$?
#     so an internal `exit 99` becomes a returnable status, and the RPM
#     downgrade still runs.
#   * If the service helper exits 99 AND the RPM downgrade succeeds, the
#     CLI preserves 99 as its exit code.
#   * stderr distinguishes the service-fatal path from a downgrade failure.
#
# Assumptions (deliberately narrow; adjust if main differs):
#   * set -e is OFF in bin/stackalign. The subshell-capture pattern is
#     silent under set -e; this test runs with `set -u` only, and invokes
#     the CLI with `bash -u` for nounset coverage, not `-e`.
#   * The snapshot path is passed as the 4th positional argument to
#     `update apply`, matching `spath="${4:-/etc/$pkg}"`.
#   * Log greps match lib/update.sh at main.

set -u

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

TARGET="nginx-1.31.0-1.el9.x86_64"
OLD="nginx-1.30.6-1.el9.x86_64"

: > "$work/nginx.conf"     # real file so the snapshot has a target
export FAKE_TARGET="$TARGET" FAKE_OLD="$OLD"

cat > "$work/dnf" <<'FAKE'
#!/usr/bin/env bash
echo "dnf $*" >> "$DNF_LOG"
case "$*" in
    *downgrade*) exit "${DNF_DOWNGRADE_RC:-0}" ;;
esac
exit 0
FAKE

# Queries succeed; state-changing verbs fail. That lands on the rollback
# path; the health check below decides 1 (recovered) vs exit 99 (fatal).
cat > "$work/systemctl" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
    *is-active*|*is-enabled*|*status*|*show*|*cat*) exit 0 ;;
esac
exit 1
FAKE

# Health check ALWAYS fails. That is what forces exit 99.
cat > "$work/nginx" <<'FAKE'
#!/usr/bin/env bash
echo "nginx $*" >> "$NGINX_LOG"
exit 1
FAKE

cat > "$work/rpm" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
    *"-qp"*) printf '%s' "$FAKE_TARGET"; exit 0 ;;
    *"-q "*) printf '%s' "$FAKE_OLD";    exit 0 ;;
esac
exit 0
FAKE
chmod +x "$work/dnf" "$work/systemctl" "$work/nginx" "$work/rpm"

export PATH="$work:$PATH"
export DNF_LOG="$work/dnf.log"
export NGINX_LOG="$work/nginx.log"
export SA_RPM_CACHE="$work/rpm-cache"
export SA_HISTORY_ROOT="$work/history"   # confirmed, not SA_HISTORY_DIR
mkdir -p "$SA_RPM_CACHE" "$SA_HISTORY_ROOT"
: > "$SA_RPM_CACHE/$TARGET.rpm"          # cache hit; no real download

fail=0
check() {
    if [ "$2" = "$3" ]; then echo "ok   $1"
    else echo "FAIL $1 (got '$2' want '$3')"; fail=1; fi
}

: > "$DNF_LOG"; : > "$NGINX_LOG"
rc=0
DNF_DOWNGRADE_RC=0 \
    bash -u "$root/bin/stackalign" update apply nginx "$TARGET" nginx "$work/nginx.conf" \
    > "$work/stdout" 2> "$work/stderr" || rc=$?

check "CLI exits 99 (helper exit 99 + successful downgrade)" "$rc" 99
check "service helper was invoked (health check ran)" \
    "$([ -s "$NGINX_LOG" ]; echo $?)" 0

check "install attempted once"  "$(grep -c 'dnf -y install' "$DNF_LOG")" 1
check "downgrade attempted once" "$(grep -c 'downgrade' "$DNF_LOG")" 1
check "downgrade used old NEVRA (not a path)" \
    "$(grep -c -- "dnf -y downgrade $OLD" "$DNF_LOG")" 1
check "no .rpm path passed to downgrade" \
    "$(grep -c -- 'downgrade .*\.rpm' "$DNF_LOG")" 0

if grep -q 'ROLLBACK FAILED' "$work/stderr"; then
    check "log omits ROLLBACK FAILED" 1 0
else
    check "log omits ROLLBACK FAILED" 0 0
fi
check "log records successful rollback" "$(grep -c 'rolled back' "$work/stderr")" 1

# Match the fatal message actually emitted by lib/service.sh at main.
if grep -Eq 'CRITICAL: manual intervention required|unhealthy after rollback' "$work/stderr"; then
    check "log identifies service-fatal path" 0 0
else
    check "log identifies service-fatal path" 1 0
fi

exit "$fail"
