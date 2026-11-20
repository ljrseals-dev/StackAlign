#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr. (@ljrseals-dev)
# Repository: https://github.com/ljrseals-dev/StackAlign
# Persistent audispd consumer. Classifies local audit events; socket correlation
# is best-effort and never treated as proof of the originating HTTP client.

set -o pipefail
TAG=stackalign-honeytrap
LOGGER_BIN="${DESKTOP_HONEYTRAP_LOGGER_BIN:-logger}"
SS_BIN="${HONEYTRAP_SS_BIN:-ss}"
FAIL2BAN_BIN="${HONEYTRAP_FAIL2BAN_BIN:-fail2ban-client}"
AUTO_BAN="${HONEYTRAP_AUTO_BAN:-0}"
BAN_JAIL="${HONEYTRAP_BAN_JAIL:-stackalign-honeytrap}"

log_event() {
    "$LOGGER_BIN" -t "$TAG" -- "$1" 2>/dev/null || :
}
is_one_of() {
    local value=$1 list=$2 item
    local -a allowed_items=()
    read -r -a allowed_items <<<"$list"
    for item in "${allowed_items[@]}"; do [[ "$value" == "$item" ]] && return 0; done
    return 1
}
classify() {
    local key=$1 exe=$2 base level=CRITICAL reason
    base=${exe##*/}
    case "$key" in
        stackalign_upload_drop)
            if is_one_of "$base" "${HONEYTRAP_UPLOAD_INFO_EXES:-php-fpm php-fpm7.4 php-fpm8.0 php-fpm8.1 php-fpm8.2 php-fpm8.3 php-fpm8.4 python python2 python3 python3.8 python3.9 python3.10 python3.11 python3.12 python3.13 nginx}"; then
                level=INFO; reason="Expected upload-queue write by $exe"
            else
                reason="Unexpected executable $exe wrote to upload queue"
            fi ;;
        stackalign_model_tamper)
            reason="Unauthorized LLM model write or attribute change by $exe" ;;
        stackalign_desktop_honeytrap)
            if is_one_of "$base" "${HONEYTRAP_X11_INFO_EXES:-Xorg Xwayland Xvfb chromium chromium-browser}"; then
                level=INFO; reason="Expected X11 runtime change by $exe"
            else
                reason="Unexpected X11 socket-directory change by $exe"
            fi ;;
        stackalign_senses_tamper)
            if is_one_of "$base" "${HONEYTRAP_SENSES_INFO_EXES:-5-senses-daemon python python3 python3.8 python3.9 python3.10 python3.11 python3.12 python3.13}"; then
                level=INFO; reason="Expected 5-Senses runtime write by $exe"
            else
                reason="Unauthorized 5-Senses runtime change by $exe"
            fi ;;
        *) return 1 ;;
    esac
    printf '%s\n%s\n%s\n' "$level" "$reason" "$base"
}
remote_peer_for_pid() {
    local pid=$1 peers peer addr
    peers="$("$SS_BIN" -Htnp 2>/dev/null | awk -v needle="pid=$pid," 'index($0, needle) {print $5}' | sort -u)"
    [[ -n "$peers" && "$(printf '%s\n' "$peers" | wc -l)" -eq 1 ]] || return 1
    peer=$peers
    if [[ "$peer" == "["*"]:"* ]]; then
        addr="${peer#\[}"; addr="${addr%%\]*}"
    else
        addr="${peer%:*}"
    fi
    [[ -n "$addr" && "$addr" != "*" && "$addr" != "0.0.0.0" && "$addr" != "::" && "$addr" != "127.0.0.1" && "$addr" != "::1" ]] || return 1
    # Restrict characters before passing the address as a single argument.
    [[ "$addr" =~ ^[0-9a-fA-F:.]+$ ]] || return 1
    printf '%s\n' "$addr"
}
handle_event() {
    local event=$1 pid exe key classification level reason remote
    [[ "$event" == *"type=SYSCALL"* ]] || return 0
    key="$(printf '%s\n' "$event" | sed -nE 's/.*key="?([^" ]+)"?.*/\1/p' | head -n1)"
    [[ "$key" == stackalign_upload_drop || "$key" == stackalign_model_tamper || "$key" == stackalign_desktop_honeytrap || "$key" == stackalign_senses_tamper ]] || return 0
    pid="$(printf '%s\n' "$event" | sed -nE 's/.* pid=([0-9]+).*/\1/p' | head -n1)"
    exe="$(printf '%s\n' "$event" | sed -nE 's/.* exe="([^"]+)".*/\1/p' | head -n1)"
    if [[ ! "$pid" =~ ^[1-9][0-9]*$ || -z "$exe" ]]; then
        log_event "[UNATTRIBUTED] Audit event key=$key lacks a valid PID or executable"
        return 0
    fi
    classification="$(classify "$key" "$exe")" || return 0
    level="$(printf '%s\n' "$classification" | sed -n '1p')"
    reason="$(printf '%s\n' "$classification" | sed -n '2p')"
    log_event "[$level] $reason (PID $pid)"
    [[ "$level" == CRITICAL ]] || return 0

    # A unique socket peer is only process-to-socket correlation. It may be a
    # reverse proxy or internal service, not the original web client.
    if ! remote="$(remote_peer_for_pid "$pid")"; then
        log_event "[UNATTRIBUTED] CRITICAL event key=$key PID=$pid executable=$exe; no unique established TCP peer"
        return 0
    fi
    log_event "CORRELATED pid=$pid peer=$remote HONEYTRAP_ACCESS key=$key executable=$exe"
    # Explicit opt-in only; use the dedicated StackAlign jail, never sshd.
    if [[ "$AUTO_BAN" == 1 ]]; then
        if "$FAIL2BAN_BIN" set "$BAN_JAIL" banip "$remote" >/dev/null 2>&1; then
            log_event "[BAN] $remote via jail=$BAN_JAIL for key=$key"
        else
            log_event "[BAN_FAILED] $remote via jail=$BAN_JAIL; verify Fail2Ban configuration"
        fi
    else
        log_event "[BAN_DISABLED] Automatic banning is disabled; peer=$remote requires review"
    fi
}
while IFS= read -r audit_record; do
    handle_event "$audit_record"
done
