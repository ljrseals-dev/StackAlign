#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/backup.sh -- mysqldump (logical), MariaBackup (physical), rclone push.
# Credentials come ONLY from a defaults file (SA_MYSQL_DEFAULTS_FILE), never argv.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_sa_bk_dir_ok() { [[ $1 == /* && $1 != *..* && $1 =~ ^/[A-Za-z0-9._/-]+$ ]]; }

# sa_backup_dump <dest_dir> -> prints the .sql.gz path
sa_backup_dump() {
    local dest=${1:-} f tmp stamp
    _sa_bk_dir_ok "$dest" || { echo "backup: bad dest dir" >&2; return 64; }
    [ -f "${SA_MYSQL_DEFAULTS_FILE:-}" ] && [ -r "$SA_MYSQL_DEFAULTS_FILE" ] || {
        echo "backup: SA_MYSQL_DEFAULTS_FILE not set/readable" >&2; return 64;
    }
    ( umask 077; mkdir -p -- "$dest" ) || return 1
    stamp=$(date +%Y%m%dT%H%M%S) || return 1
    # A private, unpredictable temporary file prevents collisions and symlink attacks.
    tmp=$(mktemp "$dest/.db-$stamp.XXXXXX") || return 1
    f="$tmp.sql.gz"
    if ( umask 077; set -o pipefail
         mysqldump --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --single-transaction \
                   --routines --triggers --all-databases | gzip -c > "$tmp" ) && ln -- "$tmp" "$f"; then
        rm -f -- "$tmp"
        printf '%s\n' "$f"
    else
        rm -f -- "$tmp"
        echo "backup: mysqldump failed or final name could not be published" >&2
        return 1
    fi
}

# sa_backup_physical <target_dir> (target must not exist yet)
sa_backup_physical() {
    local t=${1:-}
    _sa_bk_dir_ok "$t" || { echo "backup: bad target dir" >&2; return 64; }
    [ -f "${SA_MYSQL_DEFAULTS_FILE:-}" ] && [ -r "$SA_MYSQL_DEFAULTS_FILE" ] || {
        echo "backup: SA_MYSQL_DEFAULTS_FILE not set/readable" >&2; return 64;
    }
    [ ! -e "$t" ] && [ ! -L "$t" ] || { echo "backup: target exists; refusing to overwrite" >&2; return 1; }
    mariabackup --defaults-file="$SA_MYSQL_DEFAULTS_FILE" --backup --target-dir="$t" >&2 || return 1
    mariabackup --defaults-file="$SA_MYSQL_DEFAULTS_FILE" --prepare --target-dir="$t" >&2
}

# sa_backup_rclone <src_dir> <remote:path>
sa_backup_rclone() {
    local src=${1:-} remote=${2:-}
    _sa_bk_dir_ok "$src" && [ -d "$src" ] || { echo "backup: bad source dir" >&2; return 64; }
    [[ $remote =~ ^[A-Za-z0-9_-]+:[A-Za-z0-9._/-]*$ && $remote != *..* ]] || {
        echo "backup: bad remote" >&2; return 64;
    }
    rclone copy -- "$src" "$remote"
}
