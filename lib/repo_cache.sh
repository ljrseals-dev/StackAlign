#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/repo_cache.sh -- verified RPM cache keyed by exact NEVRA.
# Usage: sa_cache_get <nevra> -> prints the verified RPM path only on stdout.
# DNF diagnostics and all failures go to stderr.

: "${SA_RPM_CACHE:=/var/cache/stackalign/rpms}"

_sa_cache_valid_nevra() {
    [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9+_.:~-]*$ ]]
}

_sa_cache_rpm_nevra() {
    local result
    result=$(rpm -qp --qf '%{NEVRA}' "$1" 2>/dev/null) || return 1
    printf '%s' "$result"
}

_sa_cache_verified() {
    local file=$1 wanted=$2 actual
    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    rpm --checksig "$file" >/dev/null 2>&1 || return 1
    actual=$(_sa_cache_rpm_nevra "$file") || return 1
    [ "$actual" = "$wanted" ]
}

sa_cache_get() {
    local nevra=${1:-} target tmp candidate actual
    local -a rpms=()

    [ "$#" -eq 1 ] || { echo "sa_cache_get: expected one NEVRA" >&2; return 64; }
    _sa_cache_valid_nevra "$nevra" || {
        echo "sa_cache_get: invalid NEVRA" >&2
        return 64
    }

    mkdir -p -- "$SA_RPM_CACHE" || return 1
    target="$SA_RPM_CACHE/$nevra.rpm"

    if _sa_cache_verified "$target" "$nevra"; then
        printf '%s\n' "$target"
        return 0
    fi

    # Download into a private temporary directory. Never select an arbitrary
    # wildcard match: the download must produce exactly one RPM.
    tmp=$(mktemp -d "$SA_RPM_CACHE/.dl.XXXXXX") || return 1
    if ! dnf -y download --destdir "$tmp" "$nevra" >&2; then
        rm -rf -- "$tmp"
        return 1
    fi

    while IFS= read -r -d '' candidate; do
        rpms+=("$candidate")
    done < <(find "$tmp" -mindepth 1 -maxdepth 1 -type f -name '*.rpm' -print0)

    if [ "${#rpms[@]}" -ne 1 ]; then
        echo "sa_cache_get: expected exactly one RPM for $nevra; found ${#rpms[@]}" >&2
        rm -rf -- "$tmp"
        return 1
    fi

    candidate=${rpms[0]}
    if ! rpm --checksig "$candidate" >/dev/null 2>&1; then
        echo "sa_cache_get: RPM signature verification failed for $nevra" >&2
        rm -rf -- "$tmp"
        return 1
    fi
    actual=$(_sa_cache_rpm_nevra "$candidate") || {
        echo "sa_cache_get: cannot query downloaded RPM NEVRA" >&2
        rm -rf -- "$tmp"
        return 1
    }
    if [ "$actual" != "$nevra" ]; then
        echo "sa_cache_get: downloaded NEVRA mismatch (wanted $nevra, got $actual)" >&2
        rm -rf -- "$tmp"
        return 1
    fi

    # The target is replaced only after the downloaded RPM has passed both
    # signature and exact-identity checks.
    if ! mv -f -- "$candidate" "$target"; then
        rm -rf -- "$tmp"
        return 1
    fi
    rm -rf -- "$tmp" || return 1
    printf '%s\n' "$target"
}
