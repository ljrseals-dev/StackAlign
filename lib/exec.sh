#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# Trusted command boundary. Arguments remain distinct; argv is never logged.

_sa_exec_binary() {
    local tool=${1-} candidate
    # Unprivileged test/developer processes may supply PATH fixtures for the
    # non-mutating diagnostic adapters only. Privileged execution always uses
    # the fixed absolute mapping below; the CLI also sanitizes privileged PATH.
    if [ "${EUID:-1}" -ne 0 ]; then
        case "$tool" in curl|mysqldump)
            candidate=$(type -P -- "$tool" 2>/dev/null) || candidate=""
            if [ -n "$candidate" ] && [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
            ;;
        esac
    fi
    case "$tool" in
        systemctl) printf '%s\n' /usr/bin/systemctl ;;
        timedatectl) printf '%s\n' /usr/bin/timedatectl ;;
        nginx) printf '%s\n' /usr/sbin/nginx ;;
        httpd) printf '%s\n' /usr/sbin/httpd ;;
        apachectl) printf '%s\n' /usr/sbin/apachectl ;;
        php-fpm) printf '%s\n' /usr/sbin/php-fpm ;;
        mysql) if [ -x /usr/bin/mysql ]; then printf '%s\n' /usr/bin/mysql; else printf '%s\n' /usr/bin/mariadb; fi ;;
        mariadbd) printf '%s\n' /usr/sbin/mariadbd ;;
        mariadb) printf '%s\n' /usr/bin/mariadb ;;
        mysqladmin) printf '%s\n' /usr/bin/mysqladmin ;;
        od) printf '%s\n' /usr/bin/od ;;
        mysqldump) if [ -x /usr/bin/mysqldump ]; then printf '%s\n' /usr/bin/mysqldump; else printf '%s\n' /usr/bin/mariadb-dump; fi ;;
        mariabackup) printf '%s\n' /usr/bin/mariabackup ;;
        rclone) printf '%s\n' /usr/bin/rclone ;;
        dnf) printf '%s\n' /usr/bin/dnf ;;
        yum) printf '%s\n' /usr/bin/yum ;;
        rpm) printf '%s\n' /usr/bin/rpm ;;
        openssl) printf '%s\n' /usr/bin/openssl ;;
        argon2) printf '%s\n' /usr/bin/argon2 ;;
        useradd) printf '%s\n' /usr/sbin/useradd ;;
        userdel) printf '%s\n' /usr/sbin/userdel ;;
        groupadd) printf '%s\n' /usr/sbin/groupadd ;;
        chpasswd) printf '%s\n' /usr/sbin/chpasswd ;;
        install) printf '%s\n' /usr/bin/install ;;
        sshd) printf '%s\n' /usr/sbin/sshd ;;
        getent) printf '%s\n' /usr/bin/getent ;;
        id) printf '%s\n' /usr/bin/id ;;
        chown) printf '%s\n' /usr/bin/chown ;;
        curl) printf '%s\n' /usr/bin/curl ;;
        gpg) printf '%s\n' /usr/bin/gpg ;;
        gpgv) printf '%s\n' /usr/bin/gpgv ;;
        sha256sum) printf '%s\n' /usr/bin/sha256sum ;;
        nft) printf '%s\n' /usr/sbin/nft ;;
        firewall-cmd) printf '%s\n' /usr/bin/firewall-cmd ;;
        systemd-run) printf '%s\n' /usr/bin/systemd-run ;;
        crontab) printf '%s\n' /usr/bin/crontab ;;
        *) return 64 ;;
    esac
}

# sa_exec <approved-tool> [--timeout SECONDS] -- <argument>...
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
    [ -x /usr/bin/env ] && [ -x /usr/bin/timeout ] || { echo "exec: env/timeout unavailable; refusing execution" >&2; return 69; }
    local -a argv=("$@")
    printf 'stackalign: exec %s (timeout=%ss)\n' "$tool" "$seconds" >&2
    if [ -x /usr/bin/logger ]; then /usr/bin/logger -t stackalign "exec $tool timeout=$seconds" 2>/dev/null || true; fi
    /usr/bin/timeout --signal=TERM --kill-after=5 "${seconds}s" \
        /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C HOME=/ \
        SYSTEMD_PAGER=cat PAGER=cat "$binary" "${argv[@]}"
}

# Conservative sanitizer for captured diagnostic text. It is intentionally
# line-oriented and does not attempt to make arbitrary child output executable.
_sa_exec_redact() {
    /usr/bin/sed -E \
      -e '/^stackalign: exec /d' \
      -e 's/([Pp]assword|[Tt]oken|[Ss]ecret|[Aa]uthorization|[Aa]pi[_-]?[Kk]ey|[Pp]rivate[_-]?[Kk]ey)([[:space:]]*[:=][[:space:]]*)[^[:space:],;]+/\1\2[REDACTED]/g' \
      -e 's#(https?://)[^/@[:space:]]+:[^/@[:space:]]+@#\1[REDACTED]@#g' \
      -e 's/\x1B\[[0-9;]*[[:alpha:]]//g' \
      -e 's/[^[:print:]\t]//g'
}

# sa_exec_capture <tool> [--timeout SECONDS] -- <args...>
# Captures both streams privately, bounds output, redacts common secret forms,
# then emits sanitized diagnostics. Use only where callers need parsed stdout;
# never use it for binary output or as a general secret transport.
sa_exec_capture() {
    local tmp rc
    tmp=$(/usr/bin/mktemp) || return 1
    /usr/bin/chmod 0600 -- "$tmp" || { /usr/bin/rm -f -- "$tmp"; return 1; }
    if sa_exec "$@" >"$tmp" 2>&1; then rc=0; else rc=$?; fi
    if [ "$(/usr/bin/wc -c < "$tmp")" -gt 1048576 ]; then
        /usr/bin/rm -f -- "$tmp"
        echo "exec: captured output exceeded 1 MiB and was discarded" >&2
        return 75
    fi
    _sa_exec_redact < "$tmp"
    /usr/bin/rm -f -- "$tmp" || return 1
    return "$rc"
}
