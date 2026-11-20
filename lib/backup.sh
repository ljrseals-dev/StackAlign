#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# lib/backup.sh -- guarded logical and physical MariaDB backup helpers.
# Credentials come ONLY from an owner-only defaults file, never argv.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_sa_bk_dir_ok() {
    local path=${1:-} resolved
    [[ $path == /* && $path != / && $path != *..* && $path =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
    resolved=$(realpath -m -- "$path" 2>/dev/null) || return 1
    [[ $resolved == "$path" ]]
}

_sa_bk_defaults_ok() {
    # Absolute path; realpath -e equals supplied path; no final symlink; mode 400/600; euid owner.
    local file=${SA_MYSQL_DEFAULTS_FILE:-} mode owner resolved
    [[ $file == /* ]] || return 1
    [ -f "$file" ] && [ ! -L "$file" ] && [ -r "$file" ] || return 1
    resolved=$(/usr/bin/realpath -e -- "$file" 2>/dev/null) || return 1
    [[ $resolved == "$file" ]] || return 1
    read -r mode owner < <(/usr/bin/stat -c '%a %u' -- "$file" 2>/dev/null) || return 1
    [[ ( $mode == 400 || $mode == 600 ) && $owner == "$(/usr/bin/id -u)" ]]
}

_sa_bk_artifact_ok() {
    local path=${1:-} resolved
    [[ $path == /* && $path != *..* && $path =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
    [ ! -L "$path" ] || return 1
    resolved=$(realpath -e -- "$path" 2>/dev/null) || return 1
    [[ $resolved == "$path" ]]
}

_sa_bk_private_dir_ok() {
    local dir=${1:-} mode owner
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
    read -r mode owner < <(stat -c '%a %u' -- "$dir" 2>/dev/null) || return 1
    [[ $mode == 700 && $owner == "$(/usr/bin/id -u)" ]]
}

# sa_backup_dump <dest_dir> -> prints the .sql.gz path.
# This creates a logical all-databases dump; it does not prove restoreability.
sa_backup_dump() {
    local dest=${1:-} f tmp stamp
    _sa_bk_dir_ok "$dest" || { echo "backup: bad or symlinked destination directory" >&2; return 64; }
    _sa_bk_defaults_ok || {
        echo "backup: SA_MYSQL_DEFAULTS_FILE must be a regular, non-symlink file owned by this user with mode 400 or 600" >&2
        return 64
    }
    { if [ "${EUID:-1}" -eq 0 ]; then [ -x /usr/bin/mysqldump ] || [ -x /usr/bin/mariadb-dump ]; else command -v mysqldump >/dev/null 2>&1 || command -v mariadb-dump >/dev/null 2>&1; fi; } || { echo "backup: mysqldump is not installed" >&2; return 69; }
    [ -x /usr/bin/gzip ] || { echo "backup: gzip is not installed" >&2; return 69; }
    ( umask 077; mkdir -p -- "$dest" ) || return 1
    [ -d "$dest" ] && [ ! -L "$dest" ] && [ "$(realpath -e -- "$dest" 2>/dev/null)" = "$dest" ] && _sa_bk_private_dir_ok "$dest" || {
        echo "backup: destination must be a real directory owned by this user with mode 700" >&2; return 1;
    }
    stamp=$(date +%Y%m%dT%H%M%S) || return 1
    tmp=$(mktemp "$dest/.db-$stamp.XXXXXX") || return 1
    f="$dest/db-$stamp-${tmp##*.}.sql.gz"
    if ( umask 077; set -o pipefail
         sa_exec mysqldump -- --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --single-transaction \
                   --routines --triggers --events --hex-blob --all-databases | /usr/bin/gzip -c > "$tmp" ) && ln -- "$tmp" "$f"; then
        rm -f -- "$tmp"
        chmod 600 -- "$f" || { rm -f -- "$f"; return 1; }
        printf '%s\n' "$f"
    else
        rm -f -- "$tmp"
        echo "backup: mysqldump failed or final name could not be published" >&2
        return 1
    fi
}

# sa_backup_physical <target_dir> (target must be a new mariadb-* directory).
sa_backup_physical() {
    local target=${1:-}
    _sa_bk_dir_ok "$target" && [[ ${target##*/} == mariadb-* ]] || {
        echo "backup: target must be a safe absolute mariadb-* directory" >&2; return 64;
    }
    _sa_bk_defaults_ok || {
        echo "backup: SA_MYSQL_DEFAULTS_FILE must be a regular, non-symlink file owned by this user with mode 400 or 600" >&2
        return 64
    }
    { if [ "${EUID:-1}" -eq 0 ]; then [ -x /usr/bin/mariabackup ]; else command -v mariabackup >/dev/null 2>&1; fi; } || { echo "backup: mariabackup is not installed" >&2; return 69; }
    local parent=${target%/*}
    ( umask 077; mkdir -p -- "$parent" ) || return 1
    _sa_bk_private_dir_ok "$parent" || {
        echo "backup: parent directory must be owned by this user with mode 700" >&2; return 1;
    }
    [ ! -e "$target" ] && [ ! -L "$target" ] || {
        echo "backup: target exists; refusing to overwrite" >&2; return 1;
    }
    if ! ( umask 077; sa_exec mariabackup -- --defaults-file="$SA_MYSQL_DEFAULTS_FILE" --backup --target-dir="$target" >&2 ); then
        [ -d "$target" ] && { umask 077; : > "$target/.stackalign-incomplete"; }
        echo "backup: physical backup failed; partial data retained and marked incomplete" >&2
        return 1
    fi
    if ! ( umask 077; sa_exec mariabackup -- --defaults-file="$SA_MYSQL_DEFAULTS_FILE" --prepare --target-dir="$target" >&2 ); then
        [ -d "$target" ] && { umask 077; : > "$target/.stackalign-incomplete"; }
        echo "backup: prepare failed; backup retained and marked incomplete" >&2
        return 1
    fi
    _sa_bk_private_dir_ok "$target" || {
        [ -d "$target" ] && { umask 077; : > "$target/.stackalign-incomplete"; }
        echo "backup: physical backup directory permissions or ownership are unsafe" >&2
        return 1
    }
    printf 'prepared physical backup: %s\n' "$target"
}

# sa_backup_list <backup_dir> -- lists only recognized top-level backup artifacts.
sa_backup_list() {
    local dir=${1:-} entry state found=0 size
    _sa_bk_dir_ok "$dir" && _sa_bk_private_dir_ok "$dir" || {
        echo "backup: backup directory must be a real directory owned by this user with mode 700" >&2; return 64;
    }
    printf 'Backup artifacts in %s:\n' "$dir"
    while IFS= read -r -d '' entry; do
        [ -L "$entry" ] && continue
        if [ -f "$entry" ] && [[ $entry == *.sql.gz ]]; then
            size=$(stat -c '%s' -- "$entry") || return 1
            printf 'logical\t%s\t%s bytes\n' "${entry##*/}" "$size"
            found=1
        elif [ -d "$entry" ] && [[ ${entry##*/} == mariadb-* ]]; then
            if [ -e "$entry/.stackalign-incomplete" ]; then state=INCOMPLETE
            elif [ -f "$entry/xtrabackup_checkpoints" ]; then state=CHECKPOINTS_PRESENT
            else state=UNVERIFIED
            fi
            printf 'physical\t%s\t%s\n' "${entry##*/}" "$state"
            found=1
        fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 \( -type f -name 'db-*.sql.gz' -o -type d -name 'mariadb-*' \) -print0)
    [ "$found" -eq 1 ] || echo "no recognized backups found"
}

# sa_backup_verify <file-or-physical-dir>.
# Logical verification checks gzip integrity only, not SQL semantics or restoreability.
# Physical verification requires MariaBackup's prepared checkpoint marker.
sa_backup_verify() {
    local path=${1:-}
    _sa_bk_artifact_ok "$path" || { echo "backup: artifact path is invalid, missing, or a symlink" >&2; return 64; }
    if [ -f "$path" ] && [[ $path == *.sql.gz ]]; then
        command -v gzip >/dev/null 2>&1 || { echo "backup: gzip is not installed" >&2; return 69; }
        gzip -t -- "$path" || { echo "backup: gzip integrity check failed" >&2; return 1; }
        printf 'PASS: gzip container integrity (%s); SQL semantics and restoreability NOT VERIFIED\n' "$path"
        return 0
    fi
    if [ -d "$path" ] && [[ ${path##*/} == mariadb-* ]]; then
        _sa_bk_private_dir_ok "$path" || {
            echo "backup: physical backup directory ownership or permissions are unsafe" >&2; return 1;
        }
        [ ! -e "$path/.stackalign-incomplete" ] || {
            echo "backup: physical backup is marked incomplete" >&2; return 1;
        }
        [ -f "$path/xtrabackup_checkpoints" ] && [ ! -L "$path/xtrabackup_checkpoints" ] || {
            echo "backup: physical checkpoint file is missing" >&2; return 1;
        }
        grep -Eq '^backup_type[[:space:]]*=[[:space:]]*full-prepared[[:space:]]*$' "$path/xtrabackup_checkpoints" || {
            echo "backup: physical checkpoint is not marked full-prepared" >&2; return 1;
        }
        printf 'PASS: MariaBackup prepared checkpoint (%s); restore test NOT RUN\n' "$path"
        return 0
    fi
    echo "backup: unsupported artifact type" >&2
    return 64
}

# sa_backup_rclone <src_dir> <remote:path>. Remote encryption is provider-configured
# and is deliberately not exposed by the StackAlign CLI yet.
sa_backup_rclone() {
    local src=${1:-} remote=${2:-}
    _sa_bk_dir_ok "$src" && _sa_bk_private_dir_ok "$src" || { echo "backup: source directory must be private and owned by this user" >&2; return 64; }
    [[ $remote =~ ^[A-Za-z0-9_-]+:[A-Za-z0-9._/-]*$ && $remote != *..* ]] || {
        echo "backup: bad remote" >&2; return 64;
    }
    sa_exec rclone -- copy -- "$src" "$remote"
}
