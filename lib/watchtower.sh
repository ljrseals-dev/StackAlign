#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/watchtower.sh -- advisory audit. Observes and scores; never changes anything.

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${SA_WATCHTOWER_QUEUE:=/var/lib/stackalign/watchtower-queue.jsonl}"

_sa_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

_sa_emit_finding() {
    printf '{"severity":"%s","component":"%s","message":"%s"}\n' \
        "$(_sa_json_escape "$1")" "$(_sa_json_escape "$2")" "$(_sa_json_escape "$3")" \
        >> "$SA_WATCHTOWER_QUEUE"
}

# Repo checks only (safe in CI; queue path must be writable).
sa_watchtower_scan() {
    local root="${1:-.}"
    mkdir -p "$(dirname "$SA_WATCHTOWER_QUEUE")" || return 1
    : > "$SA_WATCHTOWER_QUEUE"
    log "Watchtower: scanning $root"

    grep -q "sa_toml_parse" "$root/lib/repo.sh" 2>/dev/null ||
        _sa_emit_finding HIGH lib/repo.sh "TOML parser not integrated."
    grep -rq "sa_cache_get" "$root/lib" 2>/dev/null ||
        _sa_emit_finding HIGH lib "RPM cache (sa_cache_get) missing."
    grep -rq "dnf -y downgrade" "$root/lib" "$root/bin" 2>/dev/null ||
        _sa_emit_finding CRITICAL bin/stackalign "Update rollback (dnf -y downgrade) missing."

    if [ -d "$root/templates/nginx" ] && [ -n "$(find "$root/templates/nginx" -type f 2>/dev/null)" ]; then
        grep -rqi "claudebot" "$root/templates/nginx" ||
            _sa_emit_finding HIGH templates/nginx "AI crawler map missing ClaudeBot."
        grep -rq "fastcgi_no_cache" "$root/templates/nginx" ||
            _sa_emit_finding CRITICAL templates/nginx "fastcgi_no_cache missing."
        grep -rq "fastcgi_cache_bypass" "$root/templates/nginx" ||
            _sa_emit_finding CRITICAL templates/nginx "fastcgi_cache_bypass missing."
    else
        _sa_emit_finding MED templates/nginx "Nginx templates missing."
    fi
    _sa_watchtower_summary
}

# Live-host checks (run on the server, usually as root).
sa_watchtower_live() {
    mkdir -p "$(dirname "$SA_WATCHTOWER_QUEUE")" || return 1
    if command -v nginx >/dev/null 2>&1 && ! nginx -t >/dev/null 2>&1; then
        _sa_emit_finding CRITICAL nginx "Live nginx -t failed."
    fi
    if command -v mysqladmin >/dev/null 2>&1 && ! mysqladmin ping >/dev/null 2>&1; then
        _sa_emit_finding CRITICAL mariadb "MariaDB not responding to ping."
    fi
    _sa_watchtower_summary
}

_sa_watchtower_summary() {
    echo "--- Watchtower findings ---"
    if [ -s "$SA_WATCHTOWER_QUEUE" ]; then
        while IFS= read -r line; do echo "  $line"; done < "$SA_WATCHTOWER_QUEUE"
    else
        echo "  No issues found."
    fi
}
