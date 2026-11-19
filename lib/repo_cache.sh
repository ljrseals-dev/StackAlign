#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/repo_cache.sh -- verified RPM cache keyed by exact NEVRA.
# Usage: sa_cache_get <nevra>   -> prints cached rpm path (only) on stdout.
# Every path returns non-zero on failure; dnf output goes to stderr.

. "$(dirname "${BASH_SOURCE[0]}")/exec.sh"

: "${SA_RPM_CACHE:=/var/cache/stackalign/rpms}"

# NEVRA charset only; no slashes, globs, spaces, or leading '-'/'.'.
_sa_nevra_valid() {
    [[ "$1" =~ ^[A-Za-z0-9_+][A-Za-z0-9._+~^:-]*$ ]] && [[ "$1" != *..* ]]
}

# Signature/integrity OK AND the file's own NEVRA equals the request.
_sa_rpm_verify() {
    local f="$1" want="$2" got
    [ -f "$f" ] && [ ! -L "$f" ] || return 1
    sa_exec rpm -- --checksig "$f" >/dev/null 2>&1 || return 1
    got="$(sa_exec_capture rpm -- -qp --qf '%{NEVRA}' -- "$f" 2>/dev/null)" || return 1
    [ "$got" = "$want" ]
}

_sa_cache_fetch() {   # $1 nevra  $2 tmpdir  $3 final path
    local nevra="$1" tmp="$2" final="$3" rpms=()
    sa_exec dnf --timeout 1800 -- -y download --destdir "$tmp" "$nevra" >&2 || return 1
    shopt -s nullglob
    rpms=("$tmp"/*.rpm)
    shopt -u nullglob
    [ "${#rpms[@]}" -eq 1 ] || return 1                 # exactly one RPM
    _sa_rpm_verify "${rpms[0]}" "$nevra" || return 1    # exact identity
    /usr/bin/ln -- "${rpms[0]}" "$final" || return 1
    /usr/bin/rm -f -- "${rpms[0]}"
}

_sa_cache_root_prepare() {
    local resolved mode owner
    if [ "${EUID:-1}" -eq 0 ]; then
        [ "$SA_RPM_CACHE" = /var/cache/stackalign/rpms ] || {
            echo "cache: privileged cache root is fixed at /var/cache/stackalign/rpms" >&2; return 64;
        }
        /usr/bin/install -d -m 0700 -- "$SA_RPM_CACHE" || return 1
        [ -d "$SA_RPM_CACHE" ] && [ ! -L "$SA_RPM_CACHE" ] || return 1
        resolved=$(/usr/bin/realpath -e -- "$SA_RPM_CACHE") || return 1
        [ "$resolved" = "$SA_RPM_CACHE" ] || return 1
        read -r mode owner < <(/usr/bin/stat -c '%a %u' -- "$SA_RPM_CACHE") || return 1
        [[ $mode = 700 && $owner = 0 ]] || {
            echo "cache: privileged cache directory must be root-owned mode 0700" >&2; return 1;
        }
    else
        /usr/bin/mkdir -m 0700 -p -- "$SA_RPM_CACHE" || return 1
        [ -d "$SA_RPM_CACHE" ] && [ ! -L "$SA_RPM_CACHE" ] || return 1
        resolved=$(/usr/bin/realpath -e -- "$SA_RPM_CACHE") || return 1
        [ "$resolved" = "$SA_RPM_CACHE" ] || return 1
        read -r mode owner < <(/usr/bin/stat -c '%a %u' -- "$SA_RPM_CACHE") || return 1
        [[ $mode = 700 && $owner = "$(/usr/bin/id -u)" ]] || return 1
    fi
}

sa_cache_get() {
    local nevra="${1:-}" final tmp rc
    _sa_nevra_valid "$nevra" || return 1
    _sa_cache_root_prepare || return $?
    final="$SA_RPM_CACHE/${nevra//:/_}.rpm"

    # Cache hit: exact name only, re-verified (signature + NEVRA).
    if _sa_rpm_verify "$final" "$nevra"; then
        printf '%s\n' "$final"; return 0
    fi
    if [ -e "$final" ] || [ -L "$final" ]; then
        [ -f "$final" ] && [ ! -L "$final" ] || {
            echo "cache: refusing non-regular or symlinked cache target" >&2; return 1;
        }
        /usr/bin/rm -f -- "$final" || return 1
    fi

    tmp="$(/usr/bin/mktemp -d "$SA_RPM_CACHE/.dl.XXXXXX")" || return 1
    _sa_cache_fetch "$nevra" "$tmp" "$final"; rc=$?
    /usr/bin/rm -rf -- "$tmp"                             # every path cleans up
    [ "$rc" -eq 0 ] || return 1
    printf '%s\n' "$final"
}
