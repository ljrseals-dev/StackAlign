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
export HONEYTRAP_X11_DIR="$TMP/x11"
export HONEYTRAP_MODELS_DIR="$TMP/models"
export HONEYTRAP_UPLOADS_DIR="$TMP/uploads"
export HONEYTRAP_SENSES_DIR="$TMP/senses"
mkdir -p "$HONEYTRAP_X11_DIR" "$HONEYTRAP_MODELS_DIR" "$HONEYTRAP_UPLOADS_DIR" "$HONEYTRAP_SENSES_DIR"
export AUDIT_DESKTOP_DEST="$TMP/audit/stackalign-desktop.rules"
export AUDIT_DESKTOP_PLUGIN_DEST="$TMP/audit/plugins/stackalign-desktop.conf"
export DESKTOP_TRIGGER_SCRIPT="$TMP/bin/stackalign-desktop-trigger.sh"
export DESKTOP_HONEYTRAP_LOGGER_BIN="$TMP/bin/logger"
export DESKTOP_HONEYTRAP_LOG="$TMP/events.log"
export HONEYTRAP_SS_BIN="$TMP/bin/ss"
export HONEYTRAP_FAIL2BAN_BIN="$TMP/bin/fail2ban-client"
mkdir -p "$TMP/bin"
cat >"$DESKTOP_HONEYTRAP_LOGGER_BIN" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DESKTOP_HONEYTRAP_LOG"
MOCK
cat >"$HONEYTRAP_SS_BIN" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat >"$HONEYTRAP_FAIL2BAN_BIN" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DESKTOP_HONEYTRAP_LOG"
MOCK
chmod +x "$DESKTOP_HONEYTRAP_LOGGER_BIN" "$HONEYTRAP_SS_BIN" "$HONEYTRAP_FAIL2BAN_BIN"

event() {
    printf '%s\n' "type=SYSCALL msg=audit(123:1): arch=c000003e syscall=257 success=yes pid=$1 exe=\"$2\" key=\"$3\"" | bash "$DESKTOP_TRIGGER_SCRIPT"
}
test_install_emits_recursive_rules_for_existing_paths() {
    install_desktop_honeytrap
    [[ -f "$AUDIT_DESKTOP_DEST" && -f "$AUDIT_DESKTOP_PLUGIN_DEST" && -x "$DESKTOP_TRIGGER_SCRIPT" ]]
    grep -q "dir=$HONEYTRAP_MODELS_DIR" "$AUDIT_DESKTOP_DEST"
    grep -q 'perm=wa -F key=stackalign_model_tamper' "$AUDIT_DESKTOP_DEST"
    grep -q 'perm=w -F key=stackalign_upload_drop' "$AUDIT_DESKTOP_DEST"
    grep -q 'path = ' "$AUDIT_DESKTOP_PLUGIN_DEST"
}
test_php_upload_is_info() {
    : >"$DESKTOP_HONEYTRAP_LOG"
    event 2000 /usr/sbin/php-fpm stackalign_upload_drop
    grep -q '\[INFO\] Expected upload-queue write' "$DESKTOP_HONEYTRAP_LOG"
    ! grep -q '\[CRITICAL\]' "$DESKTOP_HONEYTRAP_LOG"
}
test_unexpected_upload_is_critical_and_unattributed() {
    : >"$DESKTOP_HONEYTRAP_LOG"
    event 3000 /bin/bash stackalign_upload_drop
    grep -q '\[CRITICAL\] Unexpected executable' "$DESKTOP_HONEYTRAP_LOG"
    grep -q '\[UNATTRIBUTED\]' "$DESKTOP_HONEYTRAP_LOG"
    ! grep -q '\[BAN\]' "$DESKTOP_HONEYTRAP_LOG"
}
test_python_model_write_is_critical() {
    : >"$DESKTOP_HONEYTRAP_LOG"
    event 4000 /usr/bin/python3 stackalign_model_tamper
    grep -q '\[CRITICAL\] Unauthorized LLM model write' "$DESKTOP_HONEYTRAP_LOG"
}
test_x11_and_senses_have_independent_allowlists() {
    : >"$DESKTOP_HONEYTRAP_LOG"
    event 5000 /usr/bin/Xvfb stackalign_desktop_honeytrap
    grep -q '\[INFO\] Expected X11 runtime' "$DESKTOP_HONEYTRAP_LOG"
    event 5001 /tmp/rogue stackalign_senses_tamper
    grep -q '\[CRITICAL\] Unauthorized 5-Senses' "$DESKTOP_HONEYTRAP_LOG"
}
test_ban_requires_opt_in_allowlist_and_unique_peer() {
    : >"$DESKTOP_HONEYTRAP_LOG"
    export HONEYTRAP_AUTO_BAN=1
    export HONEYTRAP_BAN_IGNORE_IPS="192.0.2.10 192.0.2.11"
    cat >"$HONEYTRAP_SS_BIN" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' 'ESTAB 0 0 10.0.0.2:443 198.51.100.9:5555 users:(("worker",pid=6000,fd=3))'
MOCK
    chmod +x "$HONEYTRAP_SS_BIN"
    event 6000 /tmp/rogue stackalign_model_tamper
    grep -q 'set stackalign-honeytrap banip 198.51.100.9' "$DESKTOP_HONEYTRAP_LOG"
    : >"$DESKTOP_HONEYTRAP_LOG"
    cat >"$HONEYTRAP_SS_BIN" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' 'ESTAB 0 0 10.0.0.2:443 198.51.100.9:5555 users:(("worker",pid=6001,fd=3))'
printf '%s\n' 'ESTAB 0 0 10.0.0.2:443 198.51.100.10:5555 users:(("worker",pid=6001,fd=4))'
MOCK
    chmod +x "$HONEYTRAP_SS_BIN"
    event 6001 /tmp/rogue stackalign_model_tamper
    grep -q '\[UNATTRIBUTED\]' "$DESKTOP_HONEYTRAP_LOG"
    ! grep -q 'banip' "$DESKTOP_HONEYTRAP_LOG"
}
run() {
    local failed=0 t
    for t in test_install_emits_recursive_rules_for_existing_paths test_php_upload_is_info test_unexpected_upload_is_critical_and_unattributed test_python_model_write_is_critical test_x11_and_senses_have_independent_allowlists test_ban_requires_opt_in_allowlist_and_unique_peer; do
        if "$t"; then printf 'PASS %s\n' "$t"; else printf 'FAIL %s\n' "$t"; failed=1; fi
    done
    uninstall_desktop_honeytrap
    return "$failed"
}
run
