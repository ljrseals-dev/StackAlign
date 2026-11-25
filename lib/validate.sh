#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# Shared semantic validators. These validate data; they never execute it.

sa_validate_package_name() {
    [[ ${1-} =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$ ]] || {
        echo "validation: invalid package name" >&2
        return 64
    }
}

sa_validate_db_name() {
    [[ ${1-} =~ ^[A-Za-z][A-Za-z0-9_]{0,63}$ ]] || {
        echo "validation: invalid database identifier" >&2
        return 64
    }
}

sa_validate_site_name() {
    [[ ${1-} =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || {
        echo "validation: invalid site name" >&2
        return 64
    }
}

sa_validate_domain() {
    local domain=${1-}
    [[ ${#domain} -le 253 && $domain =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?))+$ ]] || {
        echo "validation: invalid DNS domain" >&2
        return 64
    }
}

sa_validate_service_name() {
    case ${1-} in nginx|httpd|php-fpm|mariadb|mysql|sshd) return 0 ;; esac
    echo "validation: unsupported service name" >&2
    return 64
}

sa_validate_port() {
    local port=${1-}
    [[ $port =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) || {
        echo "validation: port must be an integer from 1 to 65535" >&2
        return 64
    }
}

# Canonicalize an existing root and a candidate path without creating either.
# Reject non-canonical spellings and candidates escaping the approved root.
sa_validate_path_under_root() {
    local root=${1-} candidate=${2-} root_real candidate_real
    [[ $root == /* && $candidate == /* && $candidate != *$'\n'* && $candidate != *$'\r'* ]] || {
        echo "validation: absolute root and path required" >&2
        return 64
    }
    [ -d "$root" ] && [ ! -L "$root" ] || {
        echo "validation: approved root must be a real directory" >&2
        return 64
    }
    root_real=$(/usr/bin/realpath -e -- "$root") || return 64
    candidate_real=$(/usr/bin/realpath -m -- "$candidate") || return 64
    [[ $root_real == "$root" && $candidate_real == "$candidate" && $candidate_real == "$root_real/"* ]] || {
        echo "validation: path is non-canonical or outside approved root" >&2
        return 64
    }
}




# Stable reason and open descriptor from sa_validate_text_file_under_root.
SA_VALIDATE_FILE_REASON=""
SA_VALIDATE_FILE_FD=""
SA_VALIDATE_FILE_METADATA=""

# Validate and open a bounded text file under an approved root.
# Call directly in the current shell, never via command substitution/subshell.
# On success SA_VALIDATE_FILE_FD remains open; callers must read through
# /proc/$BASHPID/fd/$SA_VALIDATE_FILE_FD and call sa_validate_close_text_file.
# A close result of 75 means metadata changed while parsing; discard all findings.
# This pins the inspected inode so a path swap after validation cannot redirect
# the parser to a different file. The caller must source lib/exec.sh first.
# od receives only the pinned descriptor path and emits hexadecimal, not plaintext.
# Return codes: 0 valid, 64 invalid path/arguments, 65 rejected file,
# 66 missing/unreadable, 69 required helper unavailable, 74 metadata failure,
# 75 oversized or changed during inspection.
_sa_validate_text_file_fail() {
    local fd=${1-} reason=${2-} rc=${3-}
    if [[ $fd =~ ^[0-9]+$ ]] && (( fd >= 10 )); then
        exec {fd}<&- 2>/dev/null || :
    fi
    SA_VALIDATE_FILE_FD=""
    SA_VALIDATE_FILE_METADATA=""
    SA_VALIDATE_FILE_REASON=$reason
    return "$rc"
}

sa_validate_close_text_file() {
    local fd=${SA_VALIDATE_FILE_FD-} fd_path metadata fd_type fd_meta rc=0
    if [[ $fd =~ ^[0-9]+$ ]] && (( fd >= 10 )); then
        fd_path="/proc/$BASHPID/fd/$fd"
        metadata=$(/usr/bin/stat -Lc '%F|%d:%i:%s:%y:%z' -- "$fd_path" 2>/dev/null) || {
            SA_VALIDATE_FILE_REASON="descriptor_metadata_unavailable"
            rc=74
            metadata=""
        }
        if [[ -n $metadata ]]; then
            fd_type=${metadata%%|*}
            fd_meta=${metadata#*|}
            if { [[ $fd_type != "regular file" && $fd_type != "regular empty file" ]] ||
                 [[ $fd_meta != "$SA_VALIDATE_FILE_METADATA" ]]; }; then
                SA_VALIDATE_FILE_REASON="changed_during_read"
                rc=75
            fi
        fi
        exec {fd}<&- 2>/dev/null || {
            SA_VALIDATE_FILE_REASON="descriptor_close_failed"
            rc=74
        }
    fi
    SA_VALIDATE_FILE_FD=""
    SA_VALIDATE_FILE_METADATA=""
    return "$rc"
}

sa_validate_text_file_under_root() {
    local root=${1-} candidate=${2-} metadata_path metadata_fd metadata_after
    local fd_type fd_meta rest size bytes file_fd="" fd_path

    SA_VALIDATE_FILE_REASON="invalid_arguments"
    [ "$#" -eq 2 ] || return 64
    if [[ -n $SA_VALIDATE_FILE_FD ]]; then
        SA_VALIDATE_FILE_REASON="descriptor_already_open"
        return 75
    fi

    if ! sa_validate_path_under_root "$root" "$candidate" >/dev/null 2>&1; then
        SA_VALIDATE_FILE_REASON="invalid_path"
        return 64
    fi
    if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
        SA_VALIDATE_FILE_REASON="missing"
        return 66
    fi
    if [ -L "$candidate" ] || [ ! -f "$candidate" ]; then
        SA_VALIDATE_FILE_REASON="not_regular_or_symlink"
        return 65
    fi
    if [ ! -r "$candidate" ]; then
        SA_VALIDATE_FILE_REASON="not_readable"
        return 66
    fi
    if ! declare -F sa_exec >/dev/null 2>&1; then
        SA_VALIDATE_FILE_REASON="exec_wrapper_unavailable"
        return 69
    fi

    metadata_path=$(/usr/bin/stat -c '%d:%i:%s:%y:%z' -- "$candidate" 2>/dev/null) || {
        SA_VALIDATE_FILE_REASON="metadata_unavailable"
        return 74
    }
    exec {file_fd}< "$candidate" || {
        SA_VALIDATE_FILE_REASON="open_failed"
        return 66
    }
    fd_path="/proc/$BASHPID/fd/$file_fd"
    metadata_fd=$(/usr/bin/stat -Lc '%F|%d:%i:%s:%y:%z' -- "$fd_path" 2>/dev/null) || {
        _sa_validate_text_file_fail "$file_fd" "descriptor_metadata_unavailable" 74
        return $?
    }
    fd_type=${metadata_fd%%|*}
    fd_meta=${metadata_fd#*|}
    if [[ ( $fd_type != "regular file" && $fd_type != "regular empty file" ) || $fd_meta != "$metadata_path" ]]; then
        _sa_validate_text_file_fail "$file_fd" "file_changed_during_open" 75
        return $?
    fi
    if ! sa_validate_path_under_root "$root" "$candidate" >/dev/null 2>&1 ||
       [ -L "$candidate" ] || [ ! -f "$candidate" ]; then
        _sa_validate_text_file_fail "$file_fd" "path_changed_during_open" 75
        return $?
    fi
    metadata_after=$(/usr/bin/stat -c '%d:%i:%s:%y:%z' -- "$candidate" 2>/dev/null) || {
        _sa_validate_text_file_fail "$file_fd" "metadata_unavailable" 74
        return $?
    }
    if [[ $metadata_after != "$fd_meta" ]]; then
        _sa_validate_text_file_fail "$file_fd" "path_changed_during_open" 75
        return $?
    fi

    rest=${fd_meta#*:}
    rest=${rest#*:}
    size=${rest%%:*}
    [[ $size =~ ^[0-9]+$ ]] || {
        _sa_validate_text_file_fail "$file_fd" "invalid_size_metadata" 74
        return $?
    }
    if (( size > 262144 )); then
        _sa_validate_text_file_fail "$file_fd" "oversized" 75
        return $?
    fi

    # od opens the pinned /proc descriptor independently; it does not advance
    # the descriptor offset that the caller will use to parse the file.
    bytes=$(sa_exec od -- -An -v -t x1 -N "$size" -- "$fd_path" 2>/dev/null) || {
        _sa_validate_text_file_fail "$file_fd" "binary_scan_failed" 74
        return $?
    }
    if [[ $bytes =~ (^|[[:space:]])00([[:space:]]|$) ]]; then
        unset bytes
        _sa_validate_text_file_fail "$file_fd" "binary" 65
        return $?
    }
    unset bytes

    metadata_fd=$(/usr/bin/stat -Lc '%F|%d:%i:%s:%y:%z' -- "$fd_path" 2>/dev/null) || {
        _sa_validate_text_file_fail "$file_fd" "descriptor_metadata_unavailable" 74
        return $?
    }
    fd_type=${metadata_fd%%|*}
    metadata_after=${metadata_fd#*|}
    if [[ ( $fd_type != "regular file" && $fd_type != "regular empty file" ) || $metadata_after != "$fd_meta" ]]; then
        _sa_validate_text_file_fail "$file_fd" "file_changed_during_validation" 75
        return $?
    fi

    SA_VALIDATE_FILE_FD=$file_fd
    SA_VALIDATE_FILE_METADATA=$fd_meta
    SA_VALIDATE_FILE_REASON="ok"
    return 0
}
