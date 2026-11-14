#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/repo_cache.sh -- verified RPM cache keyed by exact NEVRA.
# Usage: sa_cache_get <nevra>   -> prints cached rpm path (only) on stdout.
# Every path returns non-zero on failure; dnf output goes to stderr.

: "${SA_RPM_CACHE:=/var/cache/stackalign/rpms}"

# NEVRA charset only; no slashes, globs, spaces, or leading '-'/'.'.
_sa_nevra_valid() {
    [[ "$1" =~ ^[A-Za-z0-9_+][A-Za-z0-9._+~^:-]*$ ]] && [[ "$1" != *..* ]]
}

# Signature/integrity OK AND the file's own NEVRA equals the request.
_sa_rpm_verify() {
    local f="$1" want="$2" got
    [ -f "$f" ] && [ ! -L "$f" ] || return 1
    rpm --checksig "$f" >/dev/null 2>&1 || return 1
    got="$(rpm -qp --qf '%{NEVRA}' "$f" 2>/dev/null)" || return 1
    [ "$got" = "$want" ]
}

_sa_cache_fetch() {   # $1 nevra  $2 tmpdir  $3 final path
    local nevra="$1" tmp="$2" final="$3" rpms=()
    dnf -y download --destdir "$tmp" "$nevra" >&2 || return 1
    shopt -s nullglob
    rpms=("$tmp"/*.rpm)
    shopt -u nullglob
    [ "${#rpms[@]}" -eq 1 ] || return 1                 # exactly one RPM
    _sa_rpm_verify "${rpms[0]}" "$nevra" || return 1    # exact identity
    mv -f "${rpms[0]}" "$final"
}

sa_cache_get() {
    local nevra="${1:-}" final tmp rc
    _sa_nevra_valid "$nevra" || return 1
    mkdir -p "$SA_RPM_CACHE" || return 1
    final="$SA_RPM_CACHE/${nevra//:/_}.rpm"

    # Cache hit: exact name only, re-verified (signature + NEVRA).
    if _sa_rpm_verify "$final" "$nevra"; then
        printf '%s\n' "$final"; return 0
    fi

    tmp="$(mktemp -d "$SA_RPM_CACHE/.dl.XXXXXX")" || return 1
    _sa_cache_fetch "$nevra" "$tmp" "$final"; rc=$?
    rm -rf "$tmp"                                        # every path cleans up
    [ "$rc" -eq 0 ] || return 1
    printf '%s\n' "$final"
}
