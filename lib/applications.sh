#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# lib/applications.sh -- read-only static application configuration inventory.
#
# WordPress only in v1. This module never executes or sources application files.
_sa_app_lib_dir=$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")
if ! declare -F sa_exec >/dev/null 2>&1; then
    . "$_sa_app_lib_dir/exec.sh"
fi
if ! declare -F sa_validate_text_file_under_root >/dev/null 2>&1; then
    . "$_sa_app_lib_dir/validate.sh"
fi
unset _sa_app_lib_dir

SA_WP_LITERAL_VALUE=""
SA_WP_HOST="UNKNOWN"
SA_WP_PORT="UNKNOWN"
SA_WP_SOCKET="UNKNOWN"
SA_WP_HOST_CONFIDENCE="UNKNOWN"
SA_WP_PORT_CONFIDENCE="UNKNOWN"
SA_WP_SOCKET_CONFIDENCE="UNKNOWN"

# Extract only a single-line, unescaped quoted PHP literal from a define().
# The caller must already have discarded secret-bearing lines.
_sa_wp_extract_define_literal() {
    local source_line=${1-} constant=${2-} pattern
    SA_WP_LITERAL_VALUE=""

    pattern="^[[:space:]]*define[[:space:]]*\\([[:space:]]*'${constant}'[[:space:]]*,[[:space:]]*'([^'\\\\]*)'[[:space:]]*\\)[[:space:]]*;[[:space:]]*(//.*)?$"
    if [[ $source_line =~ $pattern ]]; then
        SA_WP_LITERAL_VALUE=${BASH_REMATCH[1]}
        return 0
    fi

    # Dollar signs in double-quoted PHP strings can trigger interpolation.
    pattern="^[[:space:]]*define[[:space:]]*\\([[:space:]]*\"${constant}\"[[:space:]]*,[[:space:]]*\"([^\"\\\\$]*)\"[[:space:]]*\\)[[:space:]]*;[[:space:]]*(//.*)?$"
    if [[ $source_line =~ $pattern ]]; then
        SA_WP_LITERAL_VALUE=${BASH_REMATCH[1]}
        return 0
    fi
    return 1
}

# Parse the static DB_HOST literal without DNS lookups or connection attempts.
# This reports configured text only; it does not prove a usable endpoint.
_sa_wp_parse_db_host() {
    local value=${1-} host="" port="" socket=""

    SA_WP_HOST="UNKNOWN"
    SA_WP_PORT="UNKNOWN"
    SA_WP_SOCKET="UNKNOWN"
    SA_WP_HOST_CONFIDENCE="UNKNOWN"
    SA_WP_PORT_CONFIDENCE="UNKNOWN"
    SA_WP_SOCKET_CONFIDENCE="UNKNOWN"

    case $value in
        :/*)
            socket=${value#:}
            [[ $socket != *[[:space:]]* ]] || return 1
            SA_WP_SOCKET=$socket
            SA_WP_SOCKET_CONFIDENCE="CONFIRMED"
            return 0
            ;;
        /*)
            [[ $value != *[[:space:]]* ]] || return 1
            SA_WP_SOCKET=$value
            SA_WP_SOCKET_CONFIDENCE="CONFIRMED"
            return 0
            ;;
    esac

    if [[ $value =~ ^([^:]+):(/[^[:space:]]+)$ ]]; then
        host=${BASH_REMATCH[1]}
        socket=${BASH_REMATCH[2]}
    elif [[ $value =~ ^\\[([0-9A-Fa-f:.]+)\\](:([0-9]{1,5}))?$ ]]; then
        host=${BASH_REMATCH[1]}
        port=${BASH_REMATCH[3]-}
    elif [[ $value =~ ^([^:]+):([0-9]{1,5})$ ]]; then
        host=${BASH_REMATCH[1]}
        port=${BASH_REMATCH[2]}
    elif [[ $value =~ ^[A-Za-z0-9_.-]+$ ]]; then
        host=$value
    elif [[ $value =~ ^[0-9A-Fa-f:]+$ && $value == *:* ]]; then
        # Unbracketed IPv6 is retained as a literal host; no port is inferred.
        host=$value
    else
        return 1
    fi

    [[ $host =~ ^[A-Za-z0-9_.:-]+$ && $host != *[[:space:]]* ]] || return 1
    if [[ -n $port ]]; then
        sa_validate_port "$port" >/dev/null 2>&1 || return 1
        SA_WP_PORT=$port
        SA_WP_PORT_CONFIDENCE="CONFIRMED"
    fi
    if [[ -n $socket ]]; then
        SA_WP_SOCKET=$socket
        SA_WP_SOCKET_CONFIDENCE="CONFIRMED"
    fi

    SA_WP_HOST=$host
    SA_WP_HOST_CONFIDENCE="CONFIRMED"
    return 0
}

# sa_db_parse_wordpress_config <approved-root> <absolute-wp-config.php>
# Call directly; it opens and consumes a pinned descriptor in this shell.
# It emits a stable key:value inventory and never prints DB_USER or passwords.
sa_db_parse_wordpress_config() {
    local root=${1-} config=${2-} line trimmed
    local effective="CONFIRMED" reason="none"
    local db_name="UNKNOWN" db_name_conf="UNKNOWN" name_seen=0
    local db_host="UNKNOWN" db_host_conf="UNKNOWN" host_seen=0
    local db_port="UNKNOWN" db_port_conf="UNKNOWN"
    local db_socket="UNKNOWN" db_socket_conf="UNKNOWN"
    local db_user="UNKNOWN" db_user_conf="UNKNOWN"
    local trace_enabled=0 close_rc=0
    local fd_path user_pattern

    [ "$#" -eq 2 ] || {
        echo "applications: usage: sa_db_parse_wordpress_config <root> <wp-config.php>" >&2
        return 64
    }

    # Keep raw config lines and extracted values out of xtrace.
    case $- in *x*) trace_enabled=1; set +x ;; esac
    unset SA_WP_LITERAL_VALUE SA_WP_HOST SA_WP_PORT SA_WP_SOCKET
    SA_WP_LITERAL_VALUE=""
    SA_WP_HOST="UNKNOWN"; SA_WP_PORT="UNKNOWN"; SA_WP_SOCKET="UNKNOWN"
    SA_WP_HOST_CONFIDENCE="UNKNOWN"; SA_WP_PORT_CONFIDENCE="UNKNOWN"; SA_WP_SOCKET_CONFIDENCE="UNKNOWN"

    if ! sa_validate_text_file_under_root "$root" "$config"; then
        reason=$SA_VALIDATE_FILE_REASON
        effective="UNKNOWN"
        unset line trimmed
        if (( trace_enabled )); then set -x; fi
        printf 'application: WordPress\nconfig_file: %s\nstatus: UNKNOWN\nreason: %s\neffective_config: UNKNOWN\n' "$config" "$reason"
        printf 'app_db_name: UNKNOWN\napp_db_name_confidence: UNKNOWN\n'
        printf 'app_db_host: UNKNOWN\napp_db_host_confidence: UNKNOWN\n'
        printf 'app_db_port: UNKNOWN\napp_db_port_confidence: UNKNOWN\n'
        printf 'app_db_socket: UNKNOWN\napp_db_socket_confidence: UNKNOWN\n'
        printf 'app_db_user: UNKNOWN\napp_db_user_confidence: UNKNOWN\n'
        printf 'application_connection: UNKNOWN\napplication_connection_confidence: UNKNOWN\n'
        return 0
    fi

    fd_path="/proc/$BASHPID/fd/$SA_VALIDATE_FILE_FD"
    while IFS= read -r line || [[ -n $line ]]; do
        # Broad by design. Do not trim, lowercase-copy, regex-capture, or store
        # the value of a line containing any secret-like marker.
        case $line in
            *[Pp][Aa][Ss][Ss]*|*[Ss][Ee][Cc][Rr][Ee][Tt]*|*[Tt][Oo][Kk][Ee][Nn]*|*[Kk][Ee][Yy]*|*[Ss][Aa][Ll][Tt]*|*[Aa][Uu][Tt][Hh]*|*[Cc][Rr][Ee][Dd]*)
                effective="UNKNOWN"
                continue
                ;;
        esac

        trimmed=${line#"${line%%[![:space:]]*}"}
        trimmed=${trimmed%"${trimmed##*[![:space:]]}"}
        case $trimmed in
            ''|'#'*|'//'*) continue ;;
            '<?php'|'<?PHP'|'?>') continue ;;
            '/*'*|'*'*|'*/'*) continue ;;
        esac

        if [[ $trimmed =~ ^([!][Ii][Nn][Cc][Ll][Uu][Dd][Ee]([Dd][Ii][Rr])?|[Ii][Nn][Cc][Ll][Uu][Dd][Ee](_[Oo][Nn][Cc][Ee])?|[Rr][Ee][Qq][Uu][Ii][Rr][Ee](_[Oo][Nn][Cc][Ee])?)([[:space:]]|\\(|$) ]]; then
            effective="UNKNOWN"
            continue
        fi

        # Record only presence. Never extract or retain the username.
        user_pattern="^define[[:space:]]*\\([[:space:]]*'DB_USER'[[:space:]]*,"
        if [[ $trimmed =~ $user_pattern ]]; then
            db_user="PRESENT"
            db_user_conf="CONFIRMED"
            effective="UNKNOWN"
            continue
        fi
        user_pattern="^define[[:space:]]*\\([[:space:]]*\"DB_USER\"[[:space:]]*,"
        if [[ $trimmed =~ $user_pattern ]]; then
            db_user="PRESENT"
            db_user_conf="CONFIRMED"
            effective="UNKNOWN"
            continue
        fi

        if [[ $trimmed == *DB_NAME* ]]; then
            if (( name_seen )); then
                db_name="UNKNOWN"
                db_name_conf="UNKNOWN"
                effective="UNKNOWN"
            else
                name_seen=1
                if _sa_wp_extract_define_literal "$trimmed" DB_NAME &&
                   sa_validate_db_name "$SA_WP_LITERAL_VALUE" >/dev/null 2>&1; then
                    db_name=$SA_WP_LITERAL_VALUE
                    db_name_conf="CONFIRMED"
                else
                    db_name="UNKNOWN"
                    db_name_conf="UNKNOWN"
                    effective="UNKNOWN"
                fi
            fi
            unset SA_WP_LITERAL_VALUE
            continue
        fi

        if [[ $trimmed == *DB_HOST* ]]; then
            if (( host_seen )); then
                db_host="UNKNOWN"
                db_host_conf="UNKNOWN"
                db_port="UNKNOWN"
                db_port_conf="UNKNOWN"
                db_socket="UNKNOWN"
                db_socket_conf="UNKNOWN"
                effective="UNKNOWN"
            else
                host_seen=1
                if _sa_wp_extract_define_literal "$trimmed" DB_HOST &&
                   _sa_wp_parse_db_host "$SA_WP_LITERAL_VALUE"; then
                    db_host=$SA_WP_HOST
                    db_host_conf=$SA_WP_HOST_CONFIDENCE
                    db_port=$SA_WP_PORT
                    db_port_conf=$SA_WP_PORT_CONFIDENCE
                    db_socket=$SA_WP_SOCKET
                    db_socket_conf=$SA_WP_SOCKET_CONFIDENCE
                else
                    db_host="UNKNOWN"
                    db_host_conf="UNKNOWN"
                    db_port="UNKNOWN"
                    db_port_conf="UNKNOWN"
                    db_socket="UNKNOWN"
                    db_socket_conf="UNKNOWN"
                    effective="UNKNOWN"
                fi
            fi
            unset SA_WP_LITERAL_VALUE SA_WP_HOST SA_WP_PORT SA_WP_SOCKET
            continue
        fi

        # Any other executable PHP/config syntax is outside this static adapter.
        effective="UNKNOWN"
    done < "$fd_path"

    unset line trimmed
    if sa_validate_close_text_file; then
        close_rc=0
    else
        close_rc=$?
    fi
    if (( close_rc != 0 )); then
        reason=$SA_VALIDATE_FILE_REASON
        effective="UNKNOWN"
        db_name="UNKNOWN"; db_name_conf="UNKNOWN"
        db_host="UNKNOWN"; db_host_conf="UNKNOWN"
        db_port="UNKNOWN"; db_port_conf="UNKNOWN"
        db_socket="UNKNOWN"; db_socket_conf="UNKNOWN"
        db_user="UNKNOWN"; db_user_conf="UNKNOWN"
    fi

    unset SA_WP_LITERAL_VALUE SA_WP_HOST SA_WP_PORT SA_WP_SOCKET
    if (( trace_enabled )); then set -x; fi

    if (( close_rc != 0 )); then
        printf 'application: WordPress\nconfig_file: %s\nstatus: UNKNOWN\nreason: %s\n' "$config" "$reason"
    else
        printf 'application: WordPress\nconfig_file: %s\nstatus: INVENTORIED\nreason: none\n' "$config"
    fi
    printf 'effective_config: %s\n' "$effective"
    printf 'app_db_name: %s\napp_db_name_confidence: %s\n' "$db_name" "$db_name_conf"
    printf 'app_db_host: %s\napp_db_host_confidence: %s\n' "$db_host" "$db_host_conf"
    printf 'app_db_port: %s\napp_db_port_confidence: %s\n' "$db_port" "$db_port_conf"
    printf 'app_db_socket: %s\napp_db_socket_confidence: %s\n' "$db_socket" "$db_socket_conf"
    printf 'app_db_user: %s\napp_db_user_confidence: %s\n' "$db_user" "$db_user_conf"
    printf 'application_connection: UNKNOWN\napplication_connection_confidence: UNKNOWN\n'
    return 0
}
