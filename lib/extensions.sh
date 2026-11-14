#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/extensions.sh -- opt-in PHP extensions via DNF. Allowlist only; enabled repos only.
# ASSUMPTION: package names below match your enabled PHP repo; adjust per PHP version.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_sa_ext_pkg() {
    case ${1:-} in
        redis)   printf '%s\n' php-pecl-redis ;;
        imagick) printf '%s\n' php-pecl-imagick ;;
        ffmpeg)  printf '%s\n' ffmpeg-php ;;
        libheif) printf '%s\n' php-libheif ;;
        *) return 1 ;;
    esac
}

# sa_ext_install <comma-list>  e.g. redis,imagick
sa_ext_install() {
    local list=${1:-} e pkg
    local -a pkgs=()
    local IFS=,
    [ -n "$list" ] || return 0
    for e in $list; do
        [ -n "$e" ] || { echo "extensions: empty item is not allowed" >&2; return 64; }
        pkg="$(_sa_ext_pkg "$e")" || { echo "extensions: not allowed: $e" >&2; return 64; }
        dnf -q list --available -- "$pkg" >/dev/null 2>&1 || {
            echo "extensions: $pkg not in an enabled repo; refusing" >&2
            return 1
        }
        pkgs+=("$pkg")
    done
    dnf -y install -- "${pkgs[@]}"
}
