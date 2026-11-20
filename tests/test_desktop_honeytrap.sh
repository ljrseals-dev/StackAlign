#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr. (@ljrseals-dev)
# Repository: https://github.com/ljrseals-dev/StackAlign

set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/lib/honeytrap.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
export MOCK_SYSTEM=1
export AUDIT_DESKTOP_DEST="$TMP/audit/stackalign-desktop.rules"
export AUDIT_DESKTOP_PLUGIN_DEST="$TMP/audit/plugins/stackalign-desktop.conf"
export DESKTOP_TRIGGER_SCRIPT="$TMP/bin/stackalign-desktop-trigger.sh"
export DESKTOP_HONEYTRAP_LOGGER_BIN="$TMP/bin/logger"
export DESKTOP_HONEYTRAP_LOG="$TMP/events.log"
mkdir -p "$TMP/bin"
cat >"$DESKTOP_HONEYTRAP_LOGGER_BIN" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DESKTOP_HONEYTRAP_LOG"
MOCK
chmod +x "$DESKTOP_HONEYTRAP_LOGGER_BIN"

test_desktop_install_deploys_rule_and_dispatcher() {
    install_desktop_honeytrap
    [[ -f "$AUDIT_DESKTOP_DEST" && -f "$AUDIT_DESKTOP_PLUGIN_DEST" && -x "$DESKTOP_TRIGGER_SCRIPT" ]]
    grep -q 'dir=/dev/input' "$AUDIT_DESKTOP_DEST"
    grep -q 'stackalign_desktop_honeytrap' "$AUDIT_DESKTOP_DEST"
    grep -q 'path = ' "$AUDIT_DESKTOP_PLUGIN_DEST"
}
test_trusted_executable_is_ignored() {
    : >"$DESKTOP_HONEYTRAP_LOG"
    printf '%s\n' 'type=SYSCALL msg=audit(123:1): arch=c000003e syscall=257 success=yes pid=1234 exe="/usr/bin/Xorg" key=stackalign_desktop_honeytrap' |
        bash "$DESKTOP_TRIGGER_SCRIPT"
    ! grep -q 'CRITICAL' "$DESKTOP_HONEYTRAP_LOG"
}
test_untrusted_executable_alerts() {
    : >"$DESKTOP_HONEYTRAP_LOG"
    printf '%s\n' 'type=SYSCALL msg=audit(123:2): arch=c000003e syscall=257 success=yes pid=9999 exe="/tmp/malicious_keylogger" key=stackalign_desktop_honeytrap' |
        bash "$DESKTOP_TRIGGER_SCRIPT"
    grep -q 'CRITICAL: Unauthorized desktop disturbance detected' "$DESKTOP_HONEYTRAP_LOG"
}
test_unattributed_event_does_not_crash_or_alert() {
    : >"$DESKTOP_HONEYTRAP_LOG"
    printf '%s\n' 'type=SYSCALL msg=audit(123:3): key=stackalign_desktop_honeytrap' |
        bash "$DESKTOP_TRIGGER_SCRIPT"
    grep -q 'UNATTRIBUTED' "$DESKTOP_HONEYTRAP_LOG"
    ! grep -q 'CRITICAL' "$DESKTOP_HONEYTRAP_LOG"
}
run() {
    local failed=0 t
    for t in test_desktop_install_deploys_rule_and_dispatcher test_trusted_executable_is_ignored test_untrusted_executable_alerts test_unattributed_event_does_not_crash_or_alert; do
        if "$t"; then printf 'PASS %s\n' "$t"; else printf 'FAIL %s\n' "$t"; failed=1; fi
    done
    uninstall_desktop_honeytrap
    return "$failed"
}
run
