#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/firewall.sh -- nftables/firewalld selection and intrusion tooling.
# FTP package guard applies only to StackAlign-managed installation; it does not
# disable an independently managed server or block ordinary client/server FTP.
# FTP FXP refusal is daemon-specific and is not implemented by this firewall module.
# ASSUMPTIONS: crowdsec bouncer package name; nftables.service+firewalld both
# active is treated as "mixed" and refused.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_sa_fw_ftp() { local p=${1,,}; case $p in *vsftpd*|*pure-ftpd*|*proftpd*) return 0 ;; esac; return 1; }

# Reject attempts by StackAlign to install/manage an FTP daemon package.
# This is not a network/protocol block and must not disable external FTP.
sa_fw_refuse_ftp() {
    if _sa_fw_ftp "${1:-}"; then echo "error=ftp_daemon_refused" >&2; return 3; fi
    return 0
}

# sa_fw_validate <backend> <intrusion> <ssh_port> <http3>
sa_fw_validate() {
    [ $# -eq 4 ] || { echo "usage: sa_fw_validate backend intrusion ssh_port http3" >&2; return 64; }
    case $1 in nftables|firewalld) ;; *) echo "firewall: bad backend: $1" >&2; return 64 ;; esac
    case $2 in crowdsec|fail2ban|none) ;; *) echo "firewall: bad intrusion: $2" >&2; return 64 ;; esac
    if ! { [[ $3 =~ ^[0-9]{1,5}$ ]] && [ "$3" -ge 1 ] && [ "$3" -le 65535 ]; }; then
        echo "firewall: bad ssh_port: $3" >&2; return 64
    fi
    case $4 in on|off) ;; *) echo "firewall: bad http3: $4" >&2; return 64 ;; esac
}

# Prints the active backend; refuses to mix firewalld and nftables.service.
sa_fw_detect_backend() {
    local fwd=0 nft=0
    systemctl is-active --quiet firewalld 2>/dev/null && fwd=1
    systemctl is-active --quiet nftables 2>/dev/null && nft=1
    if [ "$fwd" -eq 1 ] && [ "$nft" -eq 1 ]; then
        echo "firewall: firewalld and nftables are both active; refusing to mix" >&2; return 1
    fi
    if [ "$fwd" -eq 1 ]; then echo firewalld; return 0; fi
    if [ "$nft" -eq 1 ] || command -v nft >/dev/null 2>&1; then echo nftables; return 0; fi
    if command -v firewall-cmd >/dev/null 2>&1; then echo firewalld; return 0; fi
    echo "firewall: no supported backend found" >&2; return 1
}

# sa_fw_render_nft <ssh_port> <http3> -> table body for an atomic nft batch.
sa_fw_render_nft() {
    sa_fw_validate nftables none "${1:-}" "${2:-}" || return 64
    printf 'table inet stackalign {\n  chain input {\n'
    printf '    type filter hook input priority 0; policy drop;\n'
    printf '    ct state invalid drop\n    ct state established,related accept\n'
    printf '    iif "lo" accept\n    ip protocol icmp accept\n'
    printf '    meta l4proto ipv6-icmp accept\n'
    printf '    tcp dport %s accept\n    tcp dport { 80, 443 } accept\n' "$1"
    [ "$2" = on ] && printf '    udp dport 443 accept\n'
    printf '  }\n}\n'
}

# Validates with nft -c first; replaces only our table in one nft transaction.
# WARNING: policy drop + a wrong ssh_port locks you out. Use a console initially.
sa_fw_apply_nft() {
    local tmp rc=0
    tmp="$(mktemp)" || return 1
    if nft list table inet stackalign >/dev/null 2>&1; then
        printf 'delete table inet stackalign\n' > "$tmp" || { rm -f -- "$tmp"; return 1; }
    fi
    sa_fw_render_nft "$@" >> "$tmp" || { rm -f -- "$tmp"; return 64; }
    if nft -c -f "$tmp"; then
        nft -f "$tmp" || rc=1
    else
        rc=1
        echo "firewall: ruleset failed nft -c; nothing loaded" >&2
    fi
    rm -f -- "$tmp"
    return "$rc"
}

# sa_fw_install_intrusion <crowdsec|fail2ban|none> -- DNF only, never vendored.
sa_fw_install_intrusion() {
    case ${1:-} in
        none) return 0 ;;
        crowdsec) dnf -y install -- crowdsec crowdsec-firewall-bouncer-nftables ;;
        fail2ban) dnf -y install -- fail2ban ;;
        *) echo "firewall: bad intrusion: ${1:-}" >&2; return 64 ;;
    esac
}
