#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
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
    [[ ${#domain} -le 253 && $domain =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$ ]] || {
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
