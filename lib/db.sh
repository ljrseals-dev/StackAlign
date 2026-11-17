#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/db.sh -- guarded MariaDB database listing and creation.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

sa_db_validate_name() {
    local name=${1:-} lower
    [[ $name =~ ^[A-Za-z][A-Za-z0-9_]{0,63}$ ]] || {
        echo "db: name must start with a letter and contain only letters, digits, and underscores (max 64)" >&2
        return 64
    }
    lower=${name,,}
    case "$lower" in
        mysql|sys|performance_schema|information_schema)
            echo "db: system database names are reserved" >&2
            return 64 ;;
    esac
}

_sa_db_defaults_ok() {
    local file=${SA_MYSQL_DEFAULTS_FILE:-} mode owner resolved
    [[ $file == /* && $file != *..* ]] && [ -f "$file" ] && [ ! -L "$file" ] && [ -r "$file" ] || return 1
    resolved=$(realpath -e -- "$file" 2>/dev/null) || return 1
    [[ $resolved == "$file" ]] || return 1
    read -r mode owner < <(stat -c '%a %u' -- "$file" 2>/dev/null) || return 1
    [[ ( $mode == 400 || $mode == 600 ) && $owner == "$(id -u)" ]]
}

_sa_db_require_client() {
    _sa_db_defaults_ok || {
        echo "db: SA_MYSQL_DEFAULTS_FILE must be a regular non-symlink file owned by this user with mode 400 or 600" >&2
        return 64
    }
    command -v mysql >/dev/null 2>&1 || {
        echo "db: mysql client is not installed" >&2
        return 69
    }
}

# sa_db_list -- read-only schema inventory.
sa_db_list() {
    _sa_db_require_client || return $?
    mysql --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --batch --skip-column-names --execute='SHOW DATABASES;'
}

# sa_db_create <database-name> -- idempotent utf8mb4 database creation.
sa_db_create() {
    local name=${1:-} existing query
    sa_db_validate_name "$name" || return $?
    _sa_db_require_client || return $?
    query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$name' LIMIT 1;"
    existing=$(mysql --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --batch --skip-column-names --execute="$query") || {
        echo "db: could not check whether database exists" >&2
        return 1
    }
    if [ "$existing" = "$name" ]; then
        printf 'database already exists: %s\n' "$name"
        return 0
    fi
    query="CREATE DATABASE \`$name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --batch --skip-column-names --execute="$query" || {
        echo "db: create failed for $name" >&2
        return 1
    }
    printf 'database created or already present: %s\n' "$name"
}

# Drop remains blocked until pre-drop backup and recovery are verified.
sa_db_drop() {
    local name=${1:-}
    sa_db_validate_name "$name" || return $?
    echo "db: DROP BLOCKED — pre-drop backup, dependency checks, confirmation, and verified rollback are not implemented; no database changes made" >&2
    return 2
}
