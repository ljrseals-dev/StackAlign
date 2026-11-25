#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# lib/db.sh -- guarded MariaDB status, listing, and creation helpers.
. "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/common.sh"
. "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/exec.sh"
. "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/validate.sh"

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
    resolved=$(/usr/bin/realpath -e -- "$file" 2>/dev/null) || return 1
    [[ $resolved == "$file" ]] || return 1
    read -r mode owner < <(/usr/bin/stat -c '%a %u' -- "$file" 2>/dev/null) || return 1
    [[ ( $mode == 400 || $mode == 600 ) && $owner == "$(/usr/bin/id -u)" ]]
}

_sa_db_client_available() { [ -x /usr/bin/mysql ] || [ -x /usr/bin/mariadb ]; }

_sa_db_require_client() {
    _sa_db_defaults_ok || {
        echo "db: SA_MYSQL_DEFAULTS_FILE must be a regular non-symlink file owned by this user with mode 400 or 600" >&2
        return 64
    }
    _sa_db_client_available || {
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

# sa_db_discover -- read-only database server metadata; never changes server state.
sa_db_discover() {
    local query='SELECT @@version_comment, @@version, @@port, @@socket, @@bind_address;'
    local result rest comment version port socket bind_address
    local comment_lc version_lc engine="UNKNOWN" engine_conf="UNKNOWN"
    local distribution="UNKNOWN" distribution_conf="UNKNOWN"
    local version_out="UNKNOWN" version_conf="UNKNOWN"
    local port_out="UNKNOWN" port_conf="UNKNOWN"
    local socket_out="UNKNOWN" socket_conf="UNKNOWN"
    local bind_out="UNKNOWN" bind_conf="UNKNOWN" comment_safe=0 comment_pattern
    local -a fields=()

    _sa_db_require_client || return $?

    if ! result=$(sa_exec mysql -- \
        --defaults-extra-file="$SA_MYSQL_DEFAULTS_FILE" \
        --batch --skip-column-names --execute="$query" 2>/dev/null); then
        echo "db: discovery query failed" >&2
        return 1
    fi

    # mysql --batch escapes embedded tabs/newlines in values. Preserve empty
    # columns while splitting the five expected tab-delimited fields.
    [[ $result != *$'\n'* && $result != *$'\r'* ]] || {
        echo "db: invalid discovery response" >&2
        return 1
    }
    rest=$result
    while [[ $rest == *$'\t'* ]]; do
        fields+=("${rest%%$'\t'*}")
        rest=${rest#*$'\t'}
    done
    fields+=("$rest")
    [ "${#fields[@]}" -eq 5 ] || {
        echo "db: invalid discovery response" >&2
        return 1
    }

    comment=${fields[0]}
    version=${fields[1]}
    port=${fields[2]}
    socket=${fields[3]}
    bind_address=${fields[4]}

    comment_pattern='^[A-Za-z0-9][A-Za-z0-9 ._()+,/:-]{0,127}$'
    if [[ $comment =~ $comment_pattern ]]; then
        comment_safe=1
    fi
    comment_lc=${comment,,}
    version_lc=${version,,}

    if [[ $comment_lc == *percona* || $version_lc == *percona* ]]; then
        engine="MySQL"
        engine_conf="CONFIRMED"
        distribution="Percona Server"
        distribution_conf="CONFIRMED"
    elif [[ $comment_lc == *mariadb* || $version_lc == *mariadb* ]]; then
        engine="MariaDB"
        engine_conf="CONFIRMED"
        if (( comment_safe )) && [[ $comment_lc != "null" ]]; then
            distribution=$comment
            distribution_conf="CONFIRMED"
        fi
    elif [[ $comment_lc == *mysql* || $version_lc == *mysql* ]]; then
        engine="MySQL"
        engine_conf="CONFIRMED"
        if (( comment_safe )) && [[ $comment_lc != "null" ]]; then
            distribution=$comment
            distribution_conf="CONFIRMED"
        fi
    fi

    if [[ $version =~ ^[0-9][A-Za-z0-9._+-]*$ ]]; then
        version_out=$version
        version_conf="CONFIRMED"
    fi

    if [[ $port != "" && $port != "NULL" ]] && sa_validate_port "$port" >/dev/null 2>&1; then
        port_out=$port
        port_conf="CONFIRMED"
    fi

    if [[ $socket == /* && $socket != *$'\n'* && $socket != *$'\r'* && $socket != *$'\t'* ]]; then
        socket_out=$socket
        socket_conf="CONFIRMED"
    fi

    if [[ -n $bind_address && ${bind_address,,} != "null" && $bind_address =~ ^[A-Za-z0-9_.:,*-]+$ ]]; then
        bind_out=$bind_address
        bind_conf="CONFIRMED"
    fi

    printf 'engine: %s\nengine_confidence: %s\n' "$engine" "$engine_conf"
    printf 'distribution: %s\ndistribution_confidence: %s\n' "$distribution" "$distribution_conf"
    printf 'version: %s\nversion_confidence: %s\n' "$version_out" "$version_conf"
    printf 'server_port: %s\nserver_port_confidence: %s\n' "$port_out" "$port_conf"
    printf 'server_socket: %s\nserver_socket_confidence: %s\n' "$socket_out" "$socket_conf"
    printf 'configured_bind_address: %s\nconfigured_bind_address_confidence: %s\n' "$bind_out" "$bind_conf"
    printf 'actual_listener: UNKNOWN\nactual_listener_confidence: UNKNOWN\n'
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
