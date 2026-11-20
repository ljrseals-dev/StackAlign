#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr. (@ljrseals-dev)
# Repository: https://github.com/ljrseals-dev/StackAlign
# Persistent audispd consumer. Alerts on input-device opens by non-allowlisted
# executables; it does not claim to identify mouse motion or keystrokes.

set -o pipefail
TAG=stackalign-desktop-honeytrap
LOGGER_BIN="${DESKTOP_HONEYTRAP_LOGGER_BIN:-logger}"
# Basenames only; administrators can replace this allowlist for their host.
TRUSTED_EXES="${DESKTOP_HONEYTRAP_TRUSTED_EXES:-Xorg Xwayland systemd-logind}"

log_event() {
    "$LOGGER_BIN" -t "$TAG" -- "$1" 2>/dev/null || :
}
is_trusted() {
    local exe=$1 allowed
    for allowed in $TRUSTED_EXES; do
        [[ "$exe" == "$allowed" ]] && return 0
    done
    return 1
}
handle_event() {
    local event=$1 pid exe
    [[ "$event" == *"type=SYSCALL"* ]] || return 0
    [[ "$event" == *"key=stackalign_desktop_honeytrap"* || "$event" == *'key="stackalign_desktop_honeytrap"'* ]] || return 0
    pid="$(printf '%s\n' "$event" | sed -nE 's/.*type=SYSCALL.* pid=([0-9]+).*/\1/p')"
    exe="$(printf '%s\n' "$event" | sed -nE 's/.* exe="([^"]+)".*/\1/p')"
    if [[ ! "$pid" =~ ^[1-9][0-9]*$ || -z "$exe" ]]; then
        log_event "UNATTRIBUTED audit event; input-device access could not be classified"
        return 0
    fi
    exe="${exe##*/}"
    if is_trusted "$exe"; then
        return 0
    fi
    log_event "CRITICAL: Unauthorized desktop disturbance detected! Process '$exe' (PID $pid) opened an input device."
}
while IFS= read -r audit_record; do
    handle_event "$audit_record"
done
