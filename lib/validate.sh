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


# Stable reason code from sa_validate_text_file_under_root.
SA_VALIDATE_FILE_REASON=""

# Validate a bounded text file under an approved root before a caller reads it.
# The caller must source lib/exec.sh first; od is used only to detect NUL bytes,
# and receives no plaintext output. File contents are never stored by this helper.
# Return codes: 0 valid, 64 invalid path/arguments, 65 rejected file,
# 66 missing/unreadable, 69 required helper unavailable, 74 metadata failure,
# 75 oversized or changed during inspection.
sa_validate_text_file_under_root() {
    local root=\${1-} candidate=\${2-} metadata_before metadata_after
    local rest size bytes

    SA_VALIDATE_FILE_REASON="invalid_arguments"
    [ "$#" -eq 2 ] || return 64

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

    metadata_before=$(/usr/bin/stat -c '%d:%i:%s:%y:%z' -- "$candidate" 2>/dev/null) || {
        SA_VALIDATE_FILE_REASON="metadata_unavailable"
        return 74
    }
    rest=\${metadata_before#*:}
    rest=\${rest#*:}
    size=\${rest%%:*}
    [[ $size =~ ^[0-9]+$ ]] || {
        SA_VALIDATE_FILE_REASON="invalid_size_metadata"
        return 74
    }
    if (( size > 262144 )); then
        SA_VALIDATE_FILE_REASON="oversized"
        return 75
    }

    # od emits hexadecimal bytes, never plaintext. The 256 KiB pre-check
    # bounds both the read and command-substitution output.
    bytes=$(sa_exec od -- -An -v -t x1 -N "$size" -- "$candidate" 2>/dev/null) || {
        SA_VALIDATE_FILE_REASON="binary_scan_failed"
        return 74
    }
    if [[ $bytes =~ (^|[[:space:]])00([[:space:]]|$) ]]; then
        SA_VALIDATE_FILE_REASON="binary"
        return 65
    }
    unset bytes

    metadata_after=$(/usr/bin/stat -c '%d:%i:%s:%y:%z' -- "$candidate" 2>/dev/null) || {
        SA_VALIDATE_FILE_REASON="metadata_unavailable"
        return 74
    }
    if [[ $metadata_before != "$metadata_after" ]]; then
        SA_VALIDATE_FILE_REASON="changed_during_validation"
        return 75
    }

    SA_VALIDATE_FILE_REASON="ok"
    return 0
}
