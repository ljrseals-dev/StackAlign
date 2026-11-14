#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/sftp.sh -- chrooted, key-only SFTP accounts (the replacement for an FTP daemon).
# Uses sshd's internal-sftp inside a Match Group drop-in. No password logins, no shell,
# no forwarding. Existing system accounts are never converted or deleted.
# ASSUMPTIONS to verify on a throwaway host: your sshd includes sshd_config.d/*.conf
# and a Match block in that drop-in does not leak into later directives (check with
# `sshd -T -C user=alice,addr=127.0.0.1`); sshd -t passes before every reload.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${SA_SFTP_GROUP:=sftponly}"
: "${SA_SFTP_BASE:=/srv/sftp}"
: "${SA_SFTP_KEYDIR:=/etc/ssh/sftp_keys}"
: "${SA_SFTP_DROPIN:=/etc/ssh/sshd_config.d/50-stackalign-sftp.conf}"

_sa_sftp_user_ok() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [ "$1" != root ]; }
_sa_sftp_key_ok() {
    [[ $1 =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com)[\ ][A-Za-z0-9+/=]+([\ ][A-Za-z0-9@._-]+)?$ ]]
}
_sa_sftp_exists()   { id -- "$1" >/dev/null 2>&1; }
_sa_sftp_in_group() { id -nG -- "$1" 2>/dev/null | tr ' ' '\n' | grep -qx -- "$SA_SFTP_GROUP"; }
_sa_sftp_group()    { getent group "$SA_SFTP_GROUP" >/dev/null 2>&1 || groupadd -- "$SA_SFTP_GROUP"; }

# OpenSSH rejects locked shadow accounts before public-key authentication.
# Store only a random, unusable-to-the-operator password hash; Match Group
# disables password and keyboard-interactive authentication for these users.
_sa_sftp_set_random_password() {
    local user=$1 secret hash
    command -v openssl >/dev/null 2>&1 || { echo "sftp: openssl is required to initialize key-only account state" >&2; return 1; }
    command -v chpasswd >/dev/null 2>&1 || { echo "sftp: chpasswd is required to initialize key-only account state" >&2; return 1; }
    secret="$(openssl rand -hex 32)" || return 1
    hash="$(openssl passwd -6 "$secret")" || { unset secret; return 1; }
    unset secret
    printf '%s:%s\n' "$user" "$hash" | chpasswd -e || { unset hash; return 1; }
    unset hash
}

sa_sftp_render() {
    printf 'Match Group %s\n' "$SA_SFTP_GROUP"
    printf '    ChrootDirectory %s/%%u\n' "$SA_SFTP_BASE"
    printf '    ForceCommand internal-sftp -d /files\n'
    printf '    AuthorizedKeysFile %s/%%u\n' "$SA_SFTP_KEYDIR"
    printf '    PasswordAuthentication no\n    KbdInteractiveAuthentication no\n'
    printf '    PermitTTY no\n    X11Forwarding no\n    AllowTcpForwarding no\n    AllowAgentForwarding no\n'
}

sa_sftp_enable() {
    local dir new backup=""
    dir="$(dirname "$SA_SFTP_DROPIN")"
    [ -d "$dir" ] || { echo "sftp: $dir does not exist" >&2; return 1; }
    _sa_sftp_group || return 1
    install -d -m 0755 -o root -g root -- "$SA_SFTP_BASE" "$SA_SFTP_KEYDIR" || return 1
    new="$(mktemp "$dir/.sa-sftp.XXXXXX")" || return 1
    sa_sftp_render > "$new" && chmod 0644 -- "$new" || { rm -f -- "$new"; return 1; }
    if [ -f "$SA_SFTP_DROPIN" ]; then
        backup="$(mktemp "$dir/.sa-sftp-bak.XXXXXX")" || { rm -f -- "$new"; return 1; }
        cp -p -- "$SA_SFTP_DROPIN" "$backup" || { rm -f -- "$new" "$backup"; return 1; }
    fi
    mv -f -- "$new" "$SA_SFTP_DROPIN" || { rm -f -- "$new" "$backup"; return 1; }
    if ! sshd -t >&2; then
        if [ -n "$backup" ]; then mv -f -- "$backup" "$SA_SFTP_DROPIN"; else rm -f -- "$SA_SFTP_DROPIN"; fi
        echo "sftp: sshd -t failed; previous configuration restored" >&2; return 1
    fi
    if ! systemctl reload sshd; then
        if [ -n "$backup" ]; then mv -f -- "$backup" "$SA_SFTP_DROPIN"; else rm -f -- "$SA_SFTP_DROPIN"; fi
        echo "sftp: reload failed; previous configuration restored" >&2; return 1
    fi
    [ -z "$backup" ] || rm -f -- "$backup"
}

sa_sftp_add_user() {
    local user=${1:-} keyfile=${2:-} key chroot tmp
    _sa_sftp_user_ok "$user" || { echo "sftp: bad username" >&2; return 64; }
    [ -f "$keyfile" ] || { echo "sftp: key file not found" >&2; return 64; }
    key="$(<"$keyfile")"
    _sa_sftp_key_ok "$key" || { echo "sftp: not a plain single-line public key" >&2; return 64; }
    if _sa_sftp_exists "$user" && ! _sa_sftp_in_group "$user"; then
        echo "sftp: $user is an existing non-SFTP account; refusing to modify it" >&2; return 1
    fi
    _sa_sftp_group || return 1
    chroot="$SA_SFTP_BASE/$user"
    if ! _sa_sftp_exists "$user"; then
        useradd -g "$SA_SFTP_GROUP" -M -d "$chroot" -s /sbin/nologin -- "$user" || return 1
        _sa_sftp_set_random_password "$user" || { userdel -- "$user" || true; return 1; }
    fi
    install -d -m 0755 -o root -g root -- "$SA_SFTP_BASE" "$SA_SFTP_KEYDIR" "$chroot" || return 1
    install -d -m 0700 -o "$user" -g "$SA_SFTP_GROUP" -- "$chroot/files" || return 1
    tmp="$(mktemp "$SA_SFTP_KEYDIR/.k.XXXXXX")" || return 1
    printf '%s\n' "$key" > "$tmp" && chmod 0644 -- "$tmp" && chown root:root -- "$tmp" &&
        mv -f -- "$tmp" "$SA_SFTP_KEYDIR/$user" || { rm -f -- "$tmp"; return 1; }
    log "sftp: $user ready (chroot $chroot, upload dir /files)"
}

sa_sftp_remove_user() {
    local user=${1:-}
    _sa_sftp_user_ok "$user" || { echo "sftp: bad username" >&2; return 64; }
    _sa_sftp_in_group "$user" || { echo "sftp: $user is not an SFTP account; refusing" >&2; return 1; }
    userdel -- "$user" || return 1
    rm -f -- "$SA_SFTP_KEYDIR/$user"
    log "sftp: removed login for $user; data kept in $SA_SFTP_BASE/$user"
}

sa_sftp_list() { getent group "$SA_SFTP_GROUP" 2>/dev/null | awk -F: '{ gsub(",", "\n", $4); print $4 }'; }
