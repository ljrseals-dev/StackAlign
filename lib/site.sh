#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/site.sh -- read-only virtual-host inventory and syntax diagnostics.
sa_site_list() {
    local root=${SA_SITE_ETC_ROOT:-/etc}
    local dir entry found=0 target rel
    printf 'web_server\tconfig_path\ttarget\n'
    for rel in nginx/conf.d nginx/sites-enabled httpd/conf.d httpd/sites-enabled; do
        dir=$root/$rel
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' entry; do
            [ -f "$entry" ] || [ -L "$entry" ] || continue
            target='regular-file'
            if [ -L "$entry" ]; then
                target=$(readlink -- "$entry") || { echo "site inventory: cannot read symlink: $entry" >&2; target='unreadable-symlink'; }
            fi
            printf '%s\t%s\t%s\n' "$rel" "$entry" "$target"
            found=1
        done < <(find "$dir" -maxdepth 1 \( -type f -o -type l \) -print0 2>/dev/null | LC_ALL=C sort -z)
    done
    [ "$found" -eq 1 ] || echo 'no vhost configuration files found in standard directories'
}
sa_site_doctor() {
    local server=${1:-all} rc=0 checked=0
    case "$server" in nginx|apache|all) ;; *) echo "usage: stackalign site doctor [nginx|apache|all]" >&2; return 64 ;; esac
    if [ "$server" = nginx ] || [ "$server" = all ]; then
        if command -v nginx >/dev/null 2>&1; then
            checked=1
            if nginx -t; then echo 'nginx_config: valid'; else echo 'nginx_config: INVALID' >&2; rc=1; fi
        elif [ "$server" = nginx ]; then echo 'nginx: not installed' >&2; return 69
        else echo 'nginx: not installed (skipped)'; fi
    fi
    if [ "$server" = apache ] || [ "$server" = all ]; then
        if command -v httpd >/dev/null 2>&1; then
            checked=1
            if httpd -t; then echo 'apache_config: valid'; else echo 'apache_config: INVALID' >&2; rc=1; fi
        elif [ "$server" = apache ]; then echo 'apache: not installed' >&2; return 69
        else echo 'apache: not installed (skipped)'; fi
    fi
    [ "$checked" -eq 1 ] || { echo 'site doctor: no supported web server binary found; no configuration was checked' >&2; return 69; }
    return "$rc"
}
sa_site_add() { echo 'site add: BLOCKED — tenant isolation and transactional deployment are not implemented; no changes made' >&2; return 2; }
sa_site_remove() { echo 'site remove: BLOCKED — dependency checks, verified backup and rollback are not implemented; no changes made' >&2; return 2; }
sa_site_isolate() { echo 'site isolate: BLOCKED — independent tenant isolation is not implemented or acceptance-tested; no changes made' >&2; return 2; }
