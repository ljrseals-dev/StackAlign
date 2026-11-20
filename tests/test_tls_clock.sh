#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/tls.sh
source "$ROOT/lib/tls.sh"

MOCK_SYNC=yes
MOCK_TIMEZONE=America/Chicago
MOCK_TIMEDATECTL_FAIL=0
MOCK_SYSTEMCTL_CALLS=0

sa_exec_capture() {
    local tool=$1
    shift
    [ "$tool" = timedatectl ] || return 99
    [ "${1-}" = -- ] || return 98
    shift
    [ "$MOCK_TIMEDATECTL_FAIL" -eq 0 ] || return 69
    case "$*" in
        "show --property=NTPSynchronized --value") printf '%s\n' "$MOCK_SYNC" ;;
        "show --property=Timezone --value") printf '%s\n' "$MOCK_TIMEZONE" ;;
        *) return 97 ;;
    esac
}

sa_exec() {
    [ "$1" = systemctl ] || return 99
    MOCK_SYSTEMCTL_CALLS=$((MOCK_SYSTEMCTL_CALLS + 1))
    return 1
}

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

out=$(sa_tls_clock_preflight) || fail "synchronized clock should pass"
[[ $out == *"synchronized=yes"* && $out == *"America/Chicago"* ]] || fail "clock status should include sync and timezone"
pass "synchronized clock accepted and timezone reported"

MOCK_SYNC=no
if sa_tls_clock_preflight >/dev/null 2>&1; then fail "unsynchronized clock must fail"; else rc=$?; fi
[ "$rc" -eq 3 ] || fail "unsynchronized clock must return 3"
pass "unsynchronized clock rejected"

if sa_tls_certbot_http01_plan example.com /tmp admin@example.com >/dev/null 2>&1; then fail "certificate planning must be blocked before downstream validation"; else rc=$?; fi
[ "$rc" -eq 3 ] || fail "certificate planning must return clock failure"
pass "certificate planning is gated before downstream work"

MOCK_SYNC=yes
MOCK_TIMEDATECTL_FAIL=1
if sa_tls_clock_preflight >/dev/null 2>&1; then fail "unverifiable clock must fail"; else rc=$?; fi
[ "$rc" -eq 3 ] || fail "unverifiable clock must return 3"
pass "unverifiable clock rejected"

MOCK_TIMEDATECTL_FAIL=0
MOCK_TIMEZONE=""
out=$(sa_tls_clock_preflight) || fail "missing timezone must not override synchronized UTC clock"
[[ $out == *"timezone=UNKNOWN"* ]] || fail "missing timezone should be reported as unknown"
pass "timezone uncertainty reported separately without misclassifying UTC synchronization"

MOCK_SYNC=no
MOCK_SYSTEMCTL_CALLS=0
if sa_tls_preflight >/dev/null 2>&1; then fail "TLS preflight must reject unsynchronized clock"; else rc=$?; fi
[ "$rc" -eq 3 ] || fail "TLS preflight should return clock failure"
[ "$MOCK_SYSTEMCTL_CALLS" -eq 0 ] || fail "scheduler inspection must not proceed after clock failure"
pass "TLS preflight stops before scheduler inspection when clock is unsynchronized"

printf '%s\n' 'TLS clock enforcement tests: PASS'
