#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/db.sh -- guarded MariaDB status, listing, and creation helpers.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
. "$(dirname "${BASH_SOURCE[0]}")/exec.sh"
. "$(dirname "${BASH_SOURCE[0]}")/validate.sh"

sa_db_validate_name() {
    local name=${1:-} lower
    sa_validate_db_name "$name" || return $?
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
    [ -x /usr/bin/mysql ] || [ -x /usr/bin/mariadb ] || {
        echo "db: mysql client is not installed" >&2
        return 69
    }
}

# sa_db_status -- read-only server and authenticated-account diagnostics.
sa_db_status() {
    local result version account
    _sa_db_require_client || return $?
    result=$(sa_exec mysql -- --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --batch --skip-column-names --execute='SELECT VERSION(), CURRENT_USER();') || {
        echo "db: connection or status query failed" >&2
        return 1
    }
    IFS=$'\t' read -r version account <<< "$result"
    [ -n "$version" ] && [ -n "$account" ] || {
        echo "db: server returned an incomplete status response" >&2
        return 1
    }
    printf 'server_version: %s\nauthenticated_account: %s\n' "$version" "$account"
}

# sa_db_list -- read-only schema inventory.
sa_db_list() {
    _sa_db_require_client || return $?
    sa_exec mysql -- --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --batch --skip-column-names --execute='SHOW DATABASES;'
}

# sa_db_user_list -- read-only database account inventory; never selects password hashes.
sa_db_user_list() {
    _sa_db_require_client || return $?
    sa_exec mysql -- --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --batch --skip-column-names --execute='SELECT User, Host FROM mysql.user ORDER BY User, Host;'
}

# sa_db_create <database-name> -- idempotent utf8mb4 database creation.
sa_db_create() {
    local name=${1:-} existing query
    sa_db_validate_name "$name" || return $?
    _sa_db_require_client || return $?
    query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$name' LIMIT 1;"
    existing=$(sa_exec mysql -- --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --batch --skip-column-names --execute="$query") || {
        echo "db: could not check whether database exists" >&2
        return 1
    }
    if [ "$existing" = "$name" ]; then
        printf 'database already exists: %s\n' "$name"
        return 0
    fi
    query="CREATE DATABASE IF NOT EXISTS \`$name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sa_exec mysql -- --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" --batch --skip-column-names --execute="$query" || {
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
