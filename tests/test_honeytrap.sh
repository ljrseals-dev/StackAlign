#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr. (@ljrseals-dev)
# Repository: https://github.com/ljrseals-dev/StackAlign

set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/lib/honeytrap.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    export MOCK_SYSTEM=1
    export TRAP_DIR="$TEST_DIR/traps" TRAP_FILE="$TEST_DIR/traps/root_ssh_backup.key"
    export AUDIT_RULE_DEST="$TEST_DIR/audit/stackalign.rules"
    export AUDIT_PLUGIN_DEST="$TEST_DIR/audit/plugins/stackalign.conf"
    export TRIGGER_SCRIPT="$TEST_DIR/bin/stackalign-honeytrap-trigger.sh"
    export FAIL2BAN_FILTER_DEST="$TEST_DIR/fail2ban/filter.d/stackalign-honeytrap.conf"
    export FAIL2BAN_JAIL_DEST="$TEST_DIR/fail2ban/jail.d/stackalign-honeytrap.conf"
}
teardown() { rm -rf -- "$TEST_DIR"; }

test_install_creates_all_artifacts() {
    install_honeytrap
    [[ -f "$TRAP_FILE" && -f "$AUDIT_RULE_DEST" && -f "$AUDIT_PLUGIN_DEST" ]]
    [[ -f "$TRIGGER_SCRIPT" && -f "$FAIL2BAN_FILTER_DEST" && -f "$FAIL2BAN_JAIL_DEST" ]]
    grep -q 'NOT A PRIVATE KEY' "$TRAP_FILE"
    grep -q -- '-w .* -p rwa -k stackalign_honeytrap' "$AUDIT_RULE_DEST"
    grep -q 'path = ' "$AUDIT_PLUGIN_DEST"
}
test_install_sets_permissions() {
    install_honeytrap
    [[ "$(stat -c '%a' "$TRAP_FILE")" == 400 ]]
    [[ "$(stat -c '%a' "$TRIGGER_SCRIPT")" == 700 ]]
}
test_install_preserves_existing_decoy() {
    mkdir -p "$TRAP_DIR"
    printf 'operator-managed marker\n' >"$TRAP_FILE"
    install_honeytrap
    grep -q 'operator-managed marker' "$TRAP_FILE"
}
test_status_reports_complete_install() {
    install_honeytrap
    status_honeytrap
}
test_uninstall_removes_all_artifacts() {
    install_honeytrap
    uninstall_honeytrap
    [[ ! -e "$TRAP_FILE" && ! -e "$AUDIT_RULE_DEST" && ! -e "$AUDIT_PLUGIN_DEST" ]]
    [[ ! -e "$TRIGGER_SCRIPT" && ! -e "$FAIL2BAN_FILTER_DEST" && ! -e "$FAIL2BAN_JAIL_DEST" ]]
}
run() {
    setup
    local failed=0 test
    for test in test_install_creates_all_artifacts test_install_sets_permissions test_install_preserves_existing_decoy test_status_reports_complete_install test_uninstall_removes_all_artifacts; do
        if "$test"; then printf 'PASS %s\n' "$test"; else printf 'FAIL %s\n' "$test"; failed=1; fi
    done
    teardown
    return "$failed"
}
run
