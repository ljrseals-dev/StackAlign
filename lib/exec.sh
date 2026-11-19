#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Trusted command boundary. Arguments remain distinct; this file never evaluates
# command strings and never logs argv (which may contain sensitive values).

_sa_exec_binary() {
    case ${1-} in
        systemctl)  printf '%s\n' /usr/bin/systemctl ;;
        nginx)      printf '%s\n' /usr/sbin/nginx ;;
        httpd)      printf '%s\n' /usr/sbin/httpd ;;
        apachectl)  printf '%s\n' /usr/sbin/apachectl ;;
        php-fpm)    printf '%s\n' /usr/sbin/php-fpm ;;
        mysql)      if [ -x /usr/bin/mysql ]; then printf '%s\n' /usr/bin/mysql; else printf '%s\n' /usr/bin/mariadb; fi ;;
        mariadb)    printf '%s\n' /usr/bin/mariadb ;;
        mysqladmin) printf '%s\n' /usr/bin/mysqladmin ;;
        dnf)        printf '%s\n' /usr/bin/dnf ;;
        rpm)        printf '%s\n' /usr/bin/rpm ;;
        openssl)    printf '%s\n' /usr/bin/openssl ;;
        argon2)     printf '%s\n' /usr/bin/argon2 ;;
        curl)       printf '%s\n' /usr/bin/curl ;;
        gpg)        printf '%s\n' /usr/bin/gpg ;;
        *) return 64 ;;
    esac
}

# sa_exec <approved-tool> [--timeout SECONDS] -- <argument>...
# The executable path is fixed above; no PATH lookup, shell parsing, or argv log.
# The child receives a deliberately small environment and a bounded runtime.
sa_exec() {
    local tool=${1-} binary seconds=30
    [ $# -ge 2 ] || { echo "exec: usage: sa_exec <tool> [--timeout seconds] -- <args...>" >&2; return 64; }
    shift
    if [ "${1-}" = --timeout ]; then
        [ $# -ge 3 ] || return 64
        seconds=${2-}
        [[ $seconds =~ ^[1-9][0-9]{0,3}$ ]] || { echo "exec: invalid timeout" >&2; return 64; }
        shift 2
    fi
    [ "${1-}" = -- ] || { echo "exec: argument separator required" >&2; return 64; }
    shift
    binary=$(_sa_exec_binary "$tool") || { echo "exec: command is not allowlisted" >&2; return 64; }
    [ -x "$binary" ] || { echo "exec: approved executable unavailable: $tool" >&2; return 69; }
    [ -x /usr/bin/env ] && [ -x /usr/bin/timeout ] || {
        echo "exec: env/timeout utilities unavailable; refusing execution" >&2
        return 69
    }
    /usr/bin/timeout --signal=TERM --kill-after=5 "${seconds}s" \
        /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C HOME=/ \
        SYSTEMD_PAGER=cat PAGER=cat "$binary" "$@"
}
