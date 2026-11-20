#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr. (@ljrseals-dev)
# Repository: https://github.com/ljrseals-dev/StackAlign
# audispd-style stdin consumer. Correlation is best-effort and fails closed.

set -uo pipefail
TAG=stackalign-honeytrap
MAX_ANCESTORS="${HONEYTRAP_MAX_ANCESTORS:-8}"
SS_BIN="${HONEYTRAP_SS_BIN:-ss}"
PS_BIN="${HONEYTRAP_PS_BIN:-ps}"
LOGGER_BIN="${HONEYTRAP_LOGGER_BIN:-logger}"

log_event() {
    "$LOGGER_BIN" -t "$TAG" -- "$1" 2>/dev/null || :
}

event="$(cat)"
pid="$(printf '%s\n' "$event" | sed -nE 's/.*type=SYSCALL.* pid=([0-9]+).*/\1/p' | head -n1)"
if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
    log_event "UNATTRIBUTED audit event; no ban attempted"
    exit 0
fi

# Walk the accessing process and its ancestors. A shell command usually does
# not own the SSH socket; the sshd session process may be an ancestor.
declare -A seen=()
matches=()
current="$pid"
for ((depth=0; depth<=MAX_ANCESTORS; depth++)); do
    [[ "$current" =~ ^[1-9][0-9]*$ ]] || break
    [[ -z "${seen[$current]+x}" ]] || break
    seen[$current]=1

    if command -v "$SS_BIN" >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ "$line" == *"pid=$current,"* ]] || continue
            # ss -tnp: state recv-q send-q local-peer remote-peer users
            read -r _ _ _ local_ep remote_ep _ <<<"$line"
            [[ "$local_ep" =~ :22$ || "$local_ep" =~ \]:22$ ]] || continue
            remote_ep="${remote_ep#[}"
            remote_ep="${remote_ep%]}"
            remote_ip="${remote_ep%:*}"
            [[ -n "$remote_ip" ]] && matches+=("$remote_ip")
        done < <("$SS_BIN" -Htnp state established 2>/dev/null)
    fi

    ppid="$("$PS_BIN" -o ppid= -p "$current" 2>/dev/null | tr -d ' ')"
    [[ "$ppid" =~ ^[1-9][0-9]*$ && "$ppid" != "$current" ]] || break
    current="$ppid"
done

# Require exactly one distinct socket peer, then validate it as globally
# routable. Python is already a StackAlign test/runtime requirement.
mapfile -t unique_matches < <(printf '%s\n' "${matches[@]}" | sed '/^$/d' | sort -u)
if [[ "${#unique_matches[@]}" -ne 1 ]]; then
    log_event "UNATTRIBUTED pid=$pid; SSH socket correlation was absent or ambiguous; no ban attempted"
    exit 0
fi
remote_ip="${unique_matches[0]}"
if ! python3 - "$remote_ip" <<'PY'
import ipaddress
import sys
try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if address.is_global else 1)
PY
then
    log_event "REJECTED pid=$pid peer=$remote_ip; address is invalid or non-global; no ban attempted"
    exit 0
fi

# Fail2Ban consumes this single, structured journal/syslog event and performs
# the ban. The trigger never invokes fail2ban-client directly.
log_event "CORRELATED pid=$pid peer=$remote_ip HONEYTRAP_ACCESS"
exit 0
