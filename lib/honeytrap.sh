#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr. (@ljrseals-dev)
# Repository: https://github.com/ljrseals-dev/StackAlign
# Honey Trap lifecycle. Safe to source; privileged work occurs only in functions.

_HONEYTRAP_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TRAP_DIR="${TRAP_DIR:-/etc/stackalign/traps}"
TRAP_FILE="${TRAP_FILE:-${TRAP_DIR}/root_ssh_backup.key}"
AUDIT_RULE_DEST="${AUDIT_RULE_DEST:-/etc/audit/rules.d/stackalign-honeytrap.rules}"
AUDIT_PLUGIN_DEST="${AUDIT_PLUGIN_DEST:-/etc/audit/plugins.d/stackalign-honeytrap.conf}"
TRIGGER_SCRIPT="${TRIGGER_SCRIPT:-/usr/local/bin/stackalign-honeytrap-trigger.sh}"
FAIL2BAN_FILTER_DEST="${FAIL2BAN_FILTER_DEST:-/etc/fail2ban/filter.d/stackalign-honeytrap.conf}"
FAIL2BAN_JAIL_DEST="${FAIL2BAN_JAIL_DEST:-/etc/fail2ban/jail.d/stackalign-honeytrap.conf}"

_honeytrap_require_root() {
    if [[ "${MOCK_SYSTEM:-0}" != 1 && "${EUID}" -ne 0 ]]; then
        printf '%s\n' "Honey Trap lifecycle requires root." >&2
        return 1
    fi
}

_honeytrap_install_file() {
    local source=$1 destination=$2 mode=$3
    install -D -m "$mode" "$source" "$destination"
}

install_honeytrap() {
    _honeytrap_require_root || return
    local tmp_rule
    printf '%s\n' "Installing StackAlign Honey Trap..."
    mkdir -p "$TRAP_DIR"
    if [[ ! -e "$TRAP_FILE" ]]; then
        umask 077
        cat >"$TRAP_FILE" <<'DECOY'
STACKALIGN HONEYTRAP DECOY — NOT A PRIVATE KEY.
This file contains no credential and must never be used for authentication.
DECOY
    fi
    chmod 0400 "$TRAP_FILE"
    if [[ "${MOCK_SYSTEM:-0}" != 1 ]]; then
        chown root:root "$TRAP_FILE"
    fi

    _honeytrap_install_file "$_HONEYTRAP_ROOT/scripts/honeytrap-trigger.sh" "$TRIGGER_SCRIPT" 0700
    _honeytrap_install_file "$_HONEYTRAP_ROOT/config/fail2ban/filter.d/stackalign-honeytrap.conf" "$FAIL2BAN_FILTER_DEST" 0644
    _honeytrap_install_file "$_HONEYTRAP_ROOT/config/fail2ban/jail.d/stackalign-honeytrap.conf" "$FAIL2BAN_JAIL_DEST" 0644

    mkdir -p "$(dirname -- "$AUDIT_RULE_DEST")"
    tmp_rule="$(mktemp)"
    printf '%s\n' "# Copyright (c) 2026 Lewis James Seals Jr." "# SPDX-License-Identifier: MIT" "-w $TRAP_FILE -p rwa -k stackalign_honeytrap" >"$tmp_rule"
    install -m 0640 "$tmp_rule" "$AUDIT_RULE_DEST"
    rm -f "$tmp_rule"

    # The audit dispatcher, not an audit rule, executes the trigger.
    local plugin_tmp
    plugin_tmp="$(mktemp)"
    printf '%s\n' "# Copyright (c) 2026 Lewis James Seals Jr." "# SPDX-License-Identifier: MIT" "active = yes" "direction = out" "path = $TRIGGER_SCRIPT" "type = always" "args =" "format = string" >"$plugin_tmp"
    install -D -m 0640 "$plugin_tmp" "$AUDIT_PLUGIN_DEST"
    rm -f "$plugin_tmp"

    if [[ "${MOCK_SYSTEM:-0}" != 1 ]]; then
        if command -v augenrules >/dev/null 2>&1; then
            augenrules --load
        elif command -v auditctl >/dev/null 2>&1; then
            auditctl -R "$AUDIT_RULE_DEST"
        else
            printf '%s\n' "Neither augenrules nor auditctl is available." >&2
            return 1
        fi
        if command -v fail2ban-client >/dev/null 2>&1; then
            fail2ban-client reload
        else
            printf '%s\n' "Fail2Ban is not installed; detection is configured but banning is inactive." >&2
        fi
    fi
    printf '%s\n' "Honey Trap files installed. Dispatcher activation and live SSH correlation require host acceptance testing."
}

uninstall_honeytrap() {
    _honeytrap_require_root || return
    rm -f -- "$TRAP_FILE" "$AUDIT_RULE_DEST" "$AUDIT_PLUGIN_DEST" "$TRIGGER_SCRIPT" "$FAIL2BAN_FILTER_DEST" "$FAIL2BAN_JAIL_DEST"
    if [[ "${MOCK_SYSTEM:-0}" != 1 ]] && command -v augenrules >/dev/null 2>&1; then
        augenrules --load
        command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client reload
    fi
    printf '%s\n' "Honey Trap configuration removed."
}

status_honeytrap() {
    local state=0
    for path in "$TRAP_FILE" "$AUDIT_RULE_DEST" "$AUDIT_PLUGIN_DEST" "$TRIGGER_SCRIPT" "$FAIL2BAN_FILTER_DEST" "$FAIL2BAN_JAIL_DEST"; do
        if [[ -e "$path" ]]; then printf 'present  %s\n' "$path"; else printf 'missing  %s\n' "$path"; state=1; fi
    done
    return "$state"
}
