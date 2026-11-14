#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/security.sh -- advisory ClamAV scan of docroots. Never quarantines or deletes.
# Findings are appended as JSON lines to SA_AUDIT_QUEUE. YARA is deferred to M7.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${SA_AUDIT_QUEUE:=/etc/stackalign/audit/queue.jsonl}"

_sa_sec_esc() {
    local s=$1
    s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# sa_security_scan <docroot>... rc 0 scan ran (findings advisory) | 2 scanner/queue error | 64 bad args
sa_security_scan() {
    [ $# -ge 1 ] || { echo "usage: sa_security_scan <docroot>..." >&2; return 64; }
    local d out rc line path sig n=0 fd
    for d in "$@"; do
        [[ $d == /* && -d $d ]] || { echo "security: not an absolute existing dir: $d" >&2; return 64; }
    done
    [[ $SA_AUDIT_QUEUE == /* ]] || { echo "security: audit queue must be an absolute path" >&2; return 64; }
    ( umask 077; mkdir -p -- "$(dirname -- "$SA_AUDIT_QUEUE")" ) || return 2
    [ ! -L "$SA_AUDIT_QUEUE" ] || { echo "security: refusing symlinked audit queue" >&2; return 2; }
    ( umask 077; : >> "$SA_AUDIT_QUEUE" ) || return 2
    chmod 600 -- "$SA_AUDIT_QUEUE" || return 2
    command -v flock >/dev/null 2>&1 || { echo "security: flock is required for queue writes" >&2; return 2; }
    exec {fd}>>"$SA_AUDIT_QUEUE" || return 2
    flock -x "$fd" || { exec {fd}>&-; return 2; }
    for d in "$@"; do
        rc=0
        out="$(clamscan -r --infected --no-summary -- "$d" 2>/dev/null)" || rc=$?
        if [ "$rc" -gt 1 ]; then
            flock -u "$fd"; exec {fd}>&-
            echo "security: clamscan failed on $d (rc=$rc)" >&2
            return 2
        fi
        while IFS= read -r line; do
            [[ $line == *" FOUND" ]] || continue
            path=${line%: *}; sig=${line##*: }; sig=${sig% FOUND}
            if ! printf '{"severity":"HIGH","component":"clamav","path":"%s","signature":"%s","action":"none"}\n' \
                "$(_sa_sec_esc "$path")" "$(_sa_sec_esc "$sig")" >&"$fd"; then
                flock -u "$fd"; exec {fd}>&-
                echo "security: failed writing audit queue" >&2
                return 2
            fi
            n=$((n + 1))
        done <<< "$out"
    done
    flock -u "$fd"; exec {fd}>&-
    echo "security: $n finding(s) queued at $SA_AUDIT_QUEUE (advisory; nothing was changed)"
}
