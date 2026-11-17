#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/site.sh -- read-only virtual-host inventory and syntax diagnostics.
sa_site_list() {
    local root=${SA_SITE_ETC_ROOT:-/etc}
    local dir entry found=0 target rel rc=0 entries
    printf 'web_server\tconfig_path_escaped\ttarget_escaped\n'
    for rel in nginx/conf.d nginx/sites-enabled httpd/conf.d httpd/sites-enabled; do
        dir=$root/$rel
        [ -d "$dir" ] || continue
        if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
            echo "site inventory: directory is not readable/searchable: $dir" >&2
            rc=1
            continue
        fi
        entries=$(mktemp "${TMPDIR:-/tmp}/stackalign-site.XXXXXX") || return 1
        if ! find "$dir" -maxdepth 1 \( -type f -o -type l \) -print0 > "$entries"; then
            echo "site inventory: failed to enumerate: $dir" >&2
            rm -f -- "$entries"
            rc=1
            continue
        fi
        while IFS= read -r -d '' entry; do
            [ -f "$entry" ] || [ -L "$entry" ] || continue
            target='regular-file'
            if [ -L "$entry" ]; then
                target=$(readlink -- "$entry") || {
                    echo "site inventory: cannot read symlink: $entry" >&2
                    rc=1
                    continue
                }
            fi
            # Bash %q keeps tabs/newlines/control characters inside one TSV cell.
            printf '%s\t' "$rel"
            printf '%q\t%q\n' "$entry" "$target"
            found=1
        done < "$entries"
        rm -f -- "$entries"
    done
    [ "$found" -eq 1 ] || echo 'no vhost configuration files found in standard directories'
    return "$rc"
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
_sa_site_valid_domain() {
    [[ ${1:-} =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]]
}
_sa_site_valid_docroot() {
    local path=${1:-} resolved
    [[ "$path" == /* && "$path" != / && "$path" != */ && "$path" != *//* ]] || return 1
    [[ "$path" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
    case "/$path/" in */./*|*/../*) return 1 ;; esac
    [ -d "$path" ] && [ -r "$path" ] && [ -x "$path" ] || return 1
    resolved=$(realpath -e -- "$path") || return 1
    [ "$resolved" = "$path" ]
}
_sa_site_require_root() {
    [ "${SA_SITE_TESTING:-0}" = 1 ] && return 0
    [ "${EUID:-$(id -u)}" -eq 0 ] || { echo 'site: apply requires root' >&2; return 1; }
}
_sa_site_nginx_dir() {
    local dir=${SA_SITE_NGINX_DIR:-/etc/nginx/conf.d} resolved
    [ -d "$dir" ] && [ ! -L "$dir" ] || { echo "site: Nginx config directory is missing or symlinked: $dir" >&2; return 1; }
    resolved=$(realpath -e -- "$dir") || return 1
    [ "$resolved" = "$dir" ] || { echo 'site: Nginx config directory resolves through a symlink; refusing' >&2; return 1; }
    printf '%s\n' "$dir"
}
_sa_site_reload_if_active() {
    command -v systemctl >/dev/null 2>&1 || { echo 'site: systemctl unavailable; configuration validated but not reloaded' >&2; return 0; }
    if systemctl is-active --quiet nginx; then systemctl reload nginx; else echo 'site: nginx is not active; configuration validated but not activated'; fi
}
sa_site_add() {
    [ "$#" -eq 3 ] || { echo 'usage: sa_site_add <domain> <document-root> <apply:0|1>' >&2; return 64; }
    local domain=$1 docroot=$2 apply=$3 dir target marker content tmp
    marker='# Managed by StackAlign site lifecycle v1'
    _sa_site_valid_domain "$domain" || { echo "site add: invalid DNS hostname: $domain" >&2; return 64; }
    _sa_site_valid_docroot "$docroot" || { echo 'site add: document root must be an existing canonical, readable, non-symlink directory using safe path characters' >&2; return 64; }
    case "$apply" in 0|1) ;; *) return 64 ;; esac
    dir=$(_sa_site_nginx_dir) || return 1
    target=$dir/stackalign-site-$domain.conf
    content=$(printf '%s\nserver {\n    listen 127.0.0.1:8080;\n    server_name %s;\n    root %s;\n    index index.html;\n    autoindex off;\n    location / { try_files \$uri \$uri/ =404; }\n    location ~ /\\. { deny all; }\n}\n' "$marker" "$domain" "$docroot")
    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ -f "$target" ] && [ ! -L "$target" ] && [ "$(cat -- "$target")" = "$content" ]; then echo "site add: unchanged ($domain)"; return 0; fi
        echo "site add: target already exists and is not identical StackAlign-managed content: $target" >&2; return 1
    fi
    if [ "$apply" -ne 1 ]; then printf 'plan: create loopback-only static Nginx vhost\n  domain=%s\n  document_root=%s\n  config=%s\nno changes made\n' "$domain" "$docroot" "$target"; return 0; fi
    _sa_site_require_root || return 1
    command -v nginx >/dev/null 2>&1 || { echo 'site add: nginx is not installed' >&2; return 69; }
    nginx -t || { echo 'site add: existing Nginx configuration is invalid; no changes made' >&2; return 1; }
    tmp=$(mktemp "$dir/.stackalign-site.XXXXXX") || return 1
    if ! printf '%s' "$content" >"$tmp" || ! chmod 0644 -- "$tmp"; then rm -f -- "$tmp"; return 1; fi
    if ! ln -- "$tmp" "$target"; then rm -f -- "$tmp"; echo 'site add: target appeared concurrently; refusing overwrite' >&2; return 1; fi
    rm -f -- "$tmp"
    if ! nginx -t; then rm -f -- "$target"; echo 'site add: generated configuration failed nginx -t; change rolled back' >&2; return 1; fi
    if ! _sa_site_reload_if_active; then
        rm -f -- "$target"
        if nginx -t && command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx; then systemctl reload nginx || echo 'CRITICAL: Nginx reload after site-add rollback also failed' >&2; fi
        echo 'site add: reload failed; generated configuration removed' >&2; return 1
    fi
    echo "site add: installed $target (static files only; PHP/TLS/public ingress not configured)"
}
sa_site_remove() {
    [ "$#" -eq 2 ] || { echo 'usage: sa_site_remove <domain> <apply:0|1>' >&2; return 64; }
    local domain=$1 apply=$2 dir target marker backup_dir backup backup_real
    marker='# Managed by StackAlign site lifecycle v1'
    _sa_site_valid_domain "$domain" || { echo "site remove: invalid DNS hostname: $domain" >&2; return 64; }
    case "$apply" in 0|1) ;; *) return 64 ;; esac
    dir=$(_sa_site_nginx_dir) || return 1
    target=$dir/stackalign-site-$domain.conf
    [ -f "$target" ] && [ ! -L "$target" ] || { echo "site remove: managed configuration not found or is a symlink: $target" >&2; return 1; }
    [ "$(head -n 1 -- "$target")" = "$marker" ] || { echo 'site remove: configuration is not StackAlign-managed; refusing' >&2; return 1; }
    if [ "$apply" -ne 1 ]; then echo "plan: archive managed vhost configuration for $domain; document root and site data will be preserved"; echo "  config=$target"; echo 'no changes made'; return 0; fi
    _sa_site_require_root || return 1
    command -v nginx >/dev/null 2>&1 || { echo 'site remove: nginx is not installed' >&2; return 69; }
    nginx -t || { echo 'site remove: existing Nginx configuration is invalid; no changes made' >&2; return 1; }
    backup_dir=${SA_SITE_BACKUP_DIR:-/var/lib/stackalign/site-backups}
    if [ -L "$backup_dir" ] || { [ -e "$backup_dir" ] && [ ! -d "$backup_dir" ]; }; then echo 'site remove: backup directory is unsafe' >&2; return 1; fi
    mkdir -p -- "$backup_dir" || return 1
    backup_real=$(realpath -e -- "$backup_dir") || return 1
    [ "$backup_real" = "$backup_dir" ] || { echo "site remove: backup path resolves through a symlink; refusing" >&2; return 1; }
    chmod 0700 -- "$backup_dir" || return 1
    if [ "${SA_SITE_TESTING:-0}" != 1 ] && [ "$(stat -c %u -- "$backup_dir")" != 0 ]; then
        echo "site remove: backup directory must be root-owned" >&2; return 1
    fi
    backup=$(mktemp "$backup_dir/${domain}-XXXXXX.conf") || return 1
    if ! cp -- "$target" "$backup" || ! chmod 0600 -- "$backup" || ! cmp -s -- "$target" "$backup"; then
        rm -f -- "$backup"
        echo "site remove: could not create verified private backup; configuration unchanged" >&2
        return 1
    fi
    rm -f -- "$target" || { echo "site remove: failed to remove configuration; backup retained at $backup" >&2; return 1; }
    if ! nginx -t; then cp -- "$backup" "$target" && chmod 0644 -- "$target" || echo 'CRITICAL: failed to restore vhost after nginx -t failure' >&2; echo "site remove: invalid resulting configuration; previous vhost restored from $backup" >&2; return 1; fi
    if ! _sa_site_reload_if_active; then
        cp -- "$backup" "$target" && chmod 0644 -- "$target" || echo 'CRITICAL: failed to restore vhost after reload failure' >&2
        if nginx -t && command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx; then systemctl reload nginx || echo 'CRITICAL: Nginx reload after site-remove rollback also failed' >&2; fi
        echo "site remove: reload failed; previous vhost restored from $backup" >&2; return 1
    fi
    echo "site remove: archived $target to $backup; document root and site data preserved"
}
sa_site_isolate() { echo 'site isolate: BLOCKED — independent tenant isolation is not implemented or acceptance-tested; no changes made' >&2; return 2; }
