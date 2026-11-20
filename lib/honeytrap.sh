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
    if [[ -L "$TRAP_DIR" || -L "$TRAP_FILE" ]]; then
        printf '%s\n' "Refusing symlinked Honey Trap directory or file." >&2
        return 1
    fi
    if [[ ! -e "$TRAP_FILE" ]]; then
        local old_umask
        old_umask="$(umask)"; umask 077
        if ! cat >"$TRAP_FILE" <<'DECOY'
STACKALIGN HONEYTRAP DECOY — NOT A PRIVATE KEY.
This file contains no credential and must never be used for authentication.
DECOY
        then umask "$old_umask"; return 1; fi
        umask "$old_umask"
    fi
    chmod 0400 "$TRAP_FILE"
    [[ "${MOCK_SYSTEM:-0}" == 1 ]] || chown root:root "$TRAP_FILE"
    _honeytrap_install_file "$_HONEYTRAP_ROOT/scripts/honeytrap-trigger.sh" "$TRIGGER_SCRIPT" 0700
    _honeytrap_install_file "$_HONEYTRAP_ROOT/config/fail2ban/filter.d/stackalign-honeytrap.conf" "$FAIL2BAN_FILTER_DEST" 0644
    _honeytrap_install_file "$_HONEYTRAP_ROOT/config/fail2ban/jail.d/stackalign-honeytrap.conf" "$FAIL2BAN_JAIL_DEST" 0644
    mkdir -p "$(dirname -- "$AUDIT_RULE_DEST")"
    tmp_rule="$(mktemp)"
    printf '%s\n' "# Copyright (c) 2026 Lewis James Seals Jr." "# SPDX-License-Identifier: MIT" "-w $TRAP_FILE -p rwa -k stackalign_honeytrap" >"$tmp_rule"
    install -m 0640 "$tmp_rule" "$AUDIT_RULE_DEST"; rm -f "$tmp_rule"
    local plugin_tmp
    plugin_tmp="$(mktemp)"
    printf '%s\n' "# Copyright (c) 2026 Lewis James Seals Jr." "# SPDX-License-Identifier: MIT" "active = yes" "direction = out" "path = $TRIGGER_SCRIPT" "type = always" "args =" "format = string" >"$plugin_tmp"
    install -D -m 0640 "$plugin_tmp" "$AUDIT_PLUGIN_DEST"; rm -f "$plugin_tmp"
    if [[ "${MOCK_SYSTEM:-0}" != 1 ]]; then
        if command -v augenrules >/dev/null 2>&1; then augenrules --load
        elif command -v auditctl >/dev/null 2>&1; then auditctl -R "$AUDIT_RULE_DEST"
        else printf '%s\n' "Neither augenrules nor auditctl is available." >&2; return 1; fi
        command -v service >/dev/null 2>&1 || { printf '%s\n' "service is unavailable; dispatcher activation is NOT verified." >&2; return 1; }
        service auditd restart
        command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client reload || :
    fi
    printf '%s\n' "Honey Trap files installed; live auditd and Fail2Ban behavior requires host acceptance testing."
}
uninstall_honeytrap() {
    _honeytrap_require_root || return
    rm -f -- "$TRAP_FILE" "$AUDIT_RULE_DEST" "$AUDIT_PLUGIN_DEST" "$TRIGGER_SCRIPT" "$FAIL2BAN_FILTER_DEST" "$FAIL2BAN_JAIL_DEST"
    if [[ "${MOCK_SYSTEM:-0}" != 1 ]]; then
        if command -v augenrules >/dev/null 2>&1; then augenrules --load
        elif command -v auditctl >/dev/null 2>&1; then auditctl -W "$TRAP_FILE" -p rwa -k stackalign_honeytrap; fi
        command -v service >/dev/null 2>&1 && service auditd restart || :
        command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client reload || :
    fi
    printf '%s\n' "Honey Trap configuration removed."
}
status_honeytrap() {
    local state=0 path
    for path in "$TRAP_FILE" "$AUDIT_RULE_DEST" "$AUDIT_PLUGIN_DEST" "$TRIGGER_SCRIPT" "$FAIL2BAN_FILTER_DEST" "$FAIL2BAN_JAIL_DEST" "$AUDIT_DESKTOP_DEST" "$AUDIT_DESKTOP_PLUGIN_DEST" "$DESKTOP_TRIGGER_SCRIPT"; do
        if [[ -e "$path" ]]; then printf 'present  %s\n' "$path"; else printf 'missing  %s\n' "$path"; state=1; fi
    done
    return "$state"
}


# Print credential and integrity guidance without generating or exposing secrets.
honeytrap_credentials_help() {
    cat <<'GUIDE'
StackAlign Honey Trap credential and integrity guidance
- No Honey Trap password, API token, or private key is created or required.
- root_ssh_backup.key is a DECOY marker, not a key; never configure it for SSH
  authentication and never put a real credential in the trap directory.
- Keep SSH administrator authentication separate. Prefer individually assigned
  SSH keys; retain a tested console/recovery path before changing sshd or bans.
- Never paste private keys or passwords into CLI arguments, shell history, logs,
  Git, or Honey Trap configuration. Use a host secret manager/password tool.
- Release SHA-256 is an integrity pin, not a password or signing key. Obtain the
  expected 64-character digest from trusted release metadata over HTTPS and compare
  it with: sha256sum <downloaded-release.tar.gz>.
- The development installer's EXPECTED_SHA256 is PLACEHOLDER and intentionally
  refuses installation until a release process pins a real digest. Do not replace
  it with a digest calculated from an untrusted download.
- Automatic IP bans are OFF by default. Before enabling them, document every
  admin, VPN, NAT, reverse-proxy, load-balancer, and monitoring address in
  HONEYTRAP_BAN_IGNORE_IPS; validate actual PID/socket topology and recovery.
GUIDE
}

# LEMP/LLM server-side resource monitoring. Paths are configurable; the
# installer never creates application directories or changes their ownership.
AUDIT_DESKTOP_SRC="${AUDIT_DESKTOP_SRC:-${_HONEYTRAP_ROOT}/config/audit/stackalign-desktop-honeytrap.rules}"
AUDIT_DESKTOP_DEST="${AUDIT_DESKTOP_DEST:-/etc/audit/rules.d/stackalign-desktop-honeytrap.rules}"
AUDIT_DESKTOP_PLUGIN_DEST="${AUDIT_DESKTOP_PLUGIN_DEST:-/etc/audit/plugins.d/stackalign-desktop-honeytrap.conf}"
DESKTOP_TRIGGER_SCRIPT="${DESKTOP_TRIGGER_SCRIPT:-/usr/local/bin/stackalign-desktop-trigger.sh}"
install_desktop_honeytrap() {
    _honeytrap_require_root || return
    [[ -r "$AUDIT_DESKTOP_SRC" ]] || { printf 'Unreadable policy template: %s\n' "$AUDIT_DESKTOP_SRC" >&2; return 1; }
    _honeytrap_install_file "$_HONEYTRAP_ROOT/scripts/desktop-trigger.sh" "$DESKTOP_TRIGGER_SCRIPT" 0700
    mkdir -p "$(dirname -- "$AUDIT_DESKTOP_DEST")"
    local tmp_rule path key perm count=0
    tmp_rule="$(mktemp)"
    {
        printf '%s\n' "# Copyright (c) 2026 Lewis James Seals Jr." "# SPDX-License-Identifier: MIT"
        for spec in \
            "${HONEYTRAP_X11_DIR:-/tmp/.X11-unix}:stackalign_desktop_honeytrap:wa" \
            "${HONEYTRAP_MODELS_DIR:-/var/www/llm-models}:stackalign_model_tamper:wa" \
            "${HONEYTRAP_UPLOADS_DIR:-/var/www/html/uploads}:stackalign_upload_drop:w" \
            "${HONEYTRAP_SENSES_DIR:-/run/5-senses}:stackalign_senses_tamper:wa"; do
            path=${spec%%:*}; spec=${spec#*:}; key=${spec%%:*}; perm=${spec##*:}
            if [[ -d "$path" && ! -L "$path" ]]; then
                printf '%s\n' "-a always,exit -F dir=${path%/}/ -F perm=$perm -F key=$key"
                count=$((count + 1))
            else
                printf 'Skipping absent or symlinked audit root: %s\n' "$path" >&2
            fi
        done
    } >"$tmp_rule"
    if [[ "$count" -eq 0 ]]; then rm -f "$tmp_rule"; printf '%s\n' "No configured LEMP/LLM audit roots exist; refusing an empty policy." >&2; return 1; fi
    install -m 0640 "$tmp_rule" "$AUDIT_DESKTOP_DEST"; rm -f "$tmp_rule"
    local plugin_tmp
    plugin_tmp="$(mktemp)"
    printf '%s\n' "# Copyright (c) 2026 Lewis James Seals Jr." "# SPDX-License-Identifier: MIT" "active = yes" "direction = out" "path = $DESKTOP_TRIGGER_SCRIPT" "type = always" "args =" "format = string" >"$plugin_tmp"
    install -D -m 0640 "$plugin_tmp" "$AUDIT_DESKTOP_PLUGIN_DEST"; rm -f "$plugin_tmp"
    if [[ "${MOCK_SYSTEM:-0}" != 1 ]]; then
        if command -v augenrules >/dev/null 2>&1; then augenrules --load
        elif command -v auditctl >/dev/null 2>&1; then auditctl -R "$AUDIT_DESKTOP_DEST"
        else printf '%s\n' "Neither augenrules nor auditctl is available." >&2; return 1; fi
        command -v service >/dev/null 2>&1 || { printf '%s\n' "service is unavailable; dispatcher activation is NOT verified." >&2; return 1; }
        service auditd restart
    fi
    printf 'LEMP/LLM Honey Trap installed with %s active audit roots. Missing roots were skipped, not created.\n' "$count"
}
uninstall_desktop_honeytrap() {
    _honeytrap_require_root || return
    rm -f -- "$AUDIT_DESKTOP_DEST" "$AUDIT_DESKTOP_PLUGIN_DEST" "$DESKTOP_TRIGGER_SCRIPT"
    if [[ "${MOCK_SYSTEM:-0}" != 1 ]]; then
        if command -v augenrules >/dev/null 2>&1; then augenrules --load
        else printf '%s\n' "Rule file removed; reload audit rules to remove active entries." >&2; fi
        command -v service >/dev/null 2>&1 && service auditd restart || :
    fi
    printf '%s\n' "LEMP/LLM Honey Trap configuration removed."
}
