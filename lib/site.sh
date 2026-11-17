#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/site.sh -- read-only virtual-host inventory and syntax diagnostics.

sa_site_list() {
    local dir entry found=0 target
    printf 'web_server\tconfig_path\ttarget\n'
    for dir in /etc/nginx/conf.d /etc/nginx/sites-enabled /etc/httpd/conf.d /etc/httpd/sites-enabled; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' entry; do
            [ -f "$entry" ] || [ -L "$entry" ] || continue
            target='regular-file'
            if [ -L "$entry" ]; then target=$(readlink -- "$entry") || target='unreadable-symlink'; fi
            printf '%s\t%s\t%s\n' "${dir#*/etc/}" "$entry" "$target"
            found=1
        done < <(find "$dir" -maxdepth 1 \( -type f -o -type l \) -print0 2>/dev/null | sort -z)
    done
    [ "$found" -eq 1 ] || echo 'no vhost configuration files found in standard directories'
}

sa_site_doctor() {
    local server=${1:-all} rc=0
    case "$server" in nginx|apache|all) ;; *) echo "usage: stackalign site doctor [nginx|apache|all]" >&2; return 64 ;; esac
    if [ "$server" = nginx ] || [ "$server" = all ]; then
        if command -v nginx >/dev/null 2>&1; then
            if nginx -t; then echo 'nginx_config: valid'; else echo 'nginx_config: INVALID' >&2; rc=1; fi
        elif [ "$server" = nginx ]; then echo 'nginx: not installed' >&2; return 69
        else echo 'nginx: not installed (skipped)'; fi
    fi
    if [ "$server" = apache ] || [ "$server" = all ]; then
        if command -v httpd >/dev/null 2>&1; then
            if httpd -t; then echo 'apache_config: valid'; else echo 'apache_config: INVALID' >&2; rc=1; fi
        elif [ "$server" = apache ]; then echo 'apache: not installed' >&2; return 69
        else echo 'apache: not installed (skipped)'; fi
    fi
    return "$rc"
}

sa_site_add() { echo 'site add: BLOCKED — tenant isolation and transactional deployment are not implemented; no changes made' >&2; return 2; }
sa_site_remove() { echo 'site remove: BLOCKED — dependency checks, verified backup and rollback are not implemented; no changes made' >&2; return 2; }
sa_site_isolate() { echo 'site isolate: BLOCKED — independent tenant isolation is not implemented or acceptance-tested; no changes made' >&2; return 2; }
