#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/egress.sh -- opt-in default-deny outbound firewall and passive LAN audit.
# Linux/nftables only. No persistence, installation, or host changes on source.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${SA_EGRESS_TABLE:=stackalign_egress}"
: "${SA_EGRESS_REVERT_UNIT:=stackalign-egress-revert}"
_sa_eg_unit_ok() { [[ $SA_EGRESS_REVERT_UNIT =~ ^[A-Za-z0-9_.@-]+$ ]]; }

_sa_eg_audit() {
    log "egress: $*"
    if command -v logger >/dev/null 2>&1; then logger -t stackalign-egress -- "$*"; fi
    return 0
}
_sa_eg_cancel_revert() {
    local unit
    # A timer may already have fired and its service may be deleting the table.
    # Stop both units before loading a new table generation.
    for unit in timer service; do
        if systemctl is-active --quiet "$SA_EGRESS_REVERT_UNIT.$unit" 2>/dev/null; then
            systemctl stop "$SA_EGRESS_REVERT_UNIT.$unit" || return 1
        fi
    done
    return 0
}
_sa_eg_table_ok() { [[ $SA_EGRESS_TABLE =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; }
_sa_eg_ip4() {
    local a=$1 p="" o
    if [[ $a == */* ]]; then p=${a#*/}; a=${a%/*}; [[ $p =~ ^[0-9]{1,2}$ ]] && [ "$p" -le 32 ] || return 1; fi
    [[ $a =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    local -a octets=(); IFS=. read -r -a octets <<< "$a"
    for o in "${octets[@]}"; do [[ $o =~ ^(0|[1-9][0-9]{0,2})$ ]] && [ "$o" -le 255 ] || return 1; done
}
_sa_eg_ip6() {
    local a=$1 p=""
    if [[ $a == */* ]]; then p=${a#*/}; a=${a%/*}; [[ $p =~ ^[0-9]{1,3}$ ]] && [ "$p" -le 128 ] || return 1; fi
    [[ $a == *:* && $a =~ ^[0-9A-Fa-f:]+$ ]]
}
_sa_eg_host() { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && $1 == *.* && ! $1 =~ ^[0-9.]+$ ]]; }
_sa_eg_port() { [[ $1 =~ ^[0-9]{1,5}$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
_sa_eg_guard_any() {
    if [[ $1 == */0 ]] && [ "${SA_EGRESS_ALLOW_ANY:-0}" != 1 ]; then
        echo "egress: $1 allows ALL destinations; set SA_EGRESS_ALLOW_ANY=1 to override" >&2
        return 1
    fi
}
sa_egress_check_entry() {
    [ $# -eq 3 ] || return 64
    case $2 in tcp|udp) ;; *) return 64 ;; esac
    _sa_eg_port "$3" || return 64
    _sa_eg_ip4 "$1" || _sa_eg_ip6 "$1" || _sa_eg_host "$1" || return 64
    _sa_eg_guard_any "$1" || return 64
}
_sa_eg_emit() {
    if _sa_eg_ip4 "$1"; then printf '    ip daddr %s %s dport %s accept\n' "$1" "$2" "$3"
    else printf '    ip6 daddr %s %s dport %s accept\n' "$1" "$2" "$3"; fi
}
_sa_eg_emit_any() {
    if _sa_eg_ip4 "$1"; then printf '    ip daddr %s accept\n' "$1"
    else printf '    ip6 daddr %s accept\n' "$1"; fi
}

# sa_egress_render <allowlist> <dns-addresses-csv> [lan-ranges-csv|none]
# Emits only the table declaration. Replacement is handled by apply as one nft transaction.
sa_egress_render() {
    local file=${1:-} dns=${2:-} lan=${3:-none} d line a b c extra ips addr
    local -a dnslist=() lanlist=()
    _sa_eg_table_ok && _sa_eg_unit_ok || { echo "egress: unsafe table or revert-unit identifier" >&2; return 64; }
    [ -f "$file" ] || { echo "egress: allowlist not found: $file" >&2; return 64; }
    [ -n "$dns" ] || { echo "egress: name at least one DNS server" >&2; return 64; }
    IFS=, read -r -a dnslist <<<"$dns"
    for d in "${dnslist[@]}"; do
        [[ $d != */* ]] && { _sa_eg_ip4 "$d" || _sa_eg_ip6 "$d"; } || { echo "egress: bad DNS server: $d" >&2; return 64; }
    done
    if [ "$lan" != none ]; then
        IFS=, read -r -a lanlist <<<"$lan"
        for d in "${lanlist[@]}"; do
            _sa_eg_ip4 "$d" || _sa_eg_ip6 "$d" || { echo "egress: bad LAN range: $d" >&2; return 64; }
            _sa_eg_guard_any "$d" || return 64
        done
    fi
    # Validate the complete file before emitting any rules.
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%%#*}
        read -r a b c extra <<<"$line"
        [ -n "${a:-}" ] || continue
        { [ -z "${extra:-}" ] && sa_egress_check_entry "$a" "${b:-}" "${c:-}"; } || {
            echo "egress: bad allowlist line: $line" >&2; return 64; }
    done < "$file"

    printf 'table inet %s {\n  chain output {\n    type filter hook output priority 0; policy drop;\n' "$SA_EGRESS_TABLE"
    printf '    oif "lo" accept\n    ct state invalid drop\n    ct state established,related accept\n'
    printf '    udp sport 68 udp dport 67 accept\n'
    printf '    ip6 daddr ff02::1:2 udp sport 546 udp dport 547 accept\n'
    printf '    icmp type { destination-unreachable, time-exceeded, parameter-problem } accept\n'
    printf '    icmpv6 type { nd-neighbor-solicit, nd-router-solicit, mld2-listener-report, packet-too-big, destination-unreachable, time-exceeded, parameter-problem } accept\n'
    for d in "${dnslist[@]}"; do
        if _sa_eg_ip4 "$d"; then
            printf '    ip daddr %s udp dport 53 accept\n    ip daddr %s tcp dport 53 accept\n' "$d" "$d"
        else
            printf '    ip6 daddr %s udp dport 53 accept\n    ip6 daddr %s tcp dport 53 accept\n' "$d" "$d"
        fi
    done
    for d in "${lanlist[@]}"; do _sa_eg_emit_any "$d"; done
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%%#*}; read -r a b c extra <<<"$line"
        [ -n "${a:-}" ] || continue
        if _sa_eg_ip4 "$a" || _sa_eg_ip6 "$a"; then _sa_eg_emit "$a" "$b" "$c"
        else
            ips="$(getent ahostsv4 "$a" 2>/dev/null | awk '{print $1}' | sort -u | head -n 16)"
            if [ -z "$ips" ]; then echo "egress: WARNING could not resolve $a; no rule written" >&2; continue; fi
            while read -r addr; do _sa_eg_ip4 "$addr" && _sa_eg_emit "$addr" "$b" "$c"; done <<<"$ips"
        fi
    done < "$file"
    printf '    counter drop\n  }\n}\n'
}

# sa_egress_apply <allowlist> <dns-csv> [lan-csv|none] [revert-seconds]
sa_egress_apply() {
    local tmp rc=0 secs=${4:-0} nftbin
    [[ $secs =~ ^[0-9]+$ ]] && { [ "$secs" -eq 0 ] || { [ "$secs" -ge 10 ] && [ "$secs" -le 3600 ]; }; } || {
        echo "egress: revert seconds must be 0 or 10-3600" >&2; return 64; }
    tmp="$(mktemp)" || return 1
    sa_egress_render "$1" "$2" "${3:-none}" > "$tmp" || { rc=$?; rm -f "$tmp"; return "$rc"; }
    # Build a single atomic replacement transaction. Never emit add-then-delete.
    if nft list table inet "$SA_EGRESS_TABLE" >/dev/null 2>&1; then
        sed -i "1i delete table inet $SA_EGRESS_TABLE" "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    if ! nft -c -f "$tmp"; then rm -f "$tmp"; echo "egress: ruleset failed nft -c; nothing loaded" >&2; return 1; fi
    # Cancel any previous timer before a new generation can be loaded, including secs=0.
    if ! _sa_eg_cancel_revert; then
        rm -f "$tmp"; echo "egress: could not stop the previous revert timer/service; refusing to load" >&2
        _sa_eg_audit "apply refused: previous revert could not be cancelled"; return 1
    fi
    if [ "$secs" -gt 0 ]; then
        nftbin="$(command -v nft)" || { rm -f "$tmp"; echo "egress: nft not found" >&2; return 1; }
        if ! systemd-run --quiet --replace --unit="$SA_EGRESS_REVERT_UNIT" --on-active="${secs}s" \
                "$nftbin" delete table inet "$SA_EGRESS_TABLE"; then
            rm -f "$tmp"; echo "egress: could not schedule auto-revert; NOTHING was loaded" >&2
            _sa_eg_audit "apply refused: revert timer could not be scheduled"; return 1
        fi
    fi
    if ! nft -f "$tmp"; then
        rm -f "$tmp"
        if [ "$secs" -gt 0 ] && ! _sa_eg_cancel_revert; then
            echo "egress: WARNING could not cancel revert timer/service" >&2
        fi
        echo "egress: load failed; nft transaction made no change" >&2
        _sa_eg_audit "apply failed: nft -f"; return 1
    fi
    rm -f "$tmp"
    _sa_eg_audit "loaded table=$SA_EGRESS_TABLE revert_seconds=$secs"
    if [ "$secs" -gt 0 ]; then echo "egress: loaded; confirm within ${secs}s or the table is removed."
    else echo "egress: loaded with NO auto-revert; undo with sa_egress_remove."; fi
}

sa_egress_confirm() {
    if systemctl is-active --quiet "$SA_EGRESS_REVERT_UNIT.timer" 2>/dev/null ||
       systemctl is-active --quiet "$SA_EGRESS_REVERT_UNIT.service" 2>/dev/null; then
        _sa_eg_cancel_revert || {
            echo "egress: could not cancel revert timer/service; rules may still revert" >&2; return 1; }
        _sa_eg_audit "revert timer/service cancelled; rules confirmed"
        echo "egress: confirmed; auto-revert cancelled."; return 0
    fi
    if nft list table inet "$SA_EGRESS_TABLE" >/dev/null 2>&1; then
        echo "egress: no revert timer pending; rules remain loaded."; return 0
    fi
    echo "egress: no revert timer pending and table is absent" >&2; return 1
}
sa_egress_remove() {
    _sa_eg_cancel_revert || {
        echo "egress: could not cancel pending revert timer/service; refusing removal" >&2; return 1; }
    if ! nft list table inet "$SA_EGRESS_TABLE" >/dev/null 2>&1; then
        echo "egress: table is not loaded; nothing to remove"; return 0
    fi
    if nft delete table inet "$SA_EGRESS_TABLE"; then
        _sa_eg_audit "removed table=$SA_EGRESS_TABLE"; return 0
    fi
    echo "egress: FAILED to delete table; firewall may still be active" >&2
    _sa_eg_audit "remove FAILED table=$SA_EGRESS_TABLE"; return 1
}

# sa_lan_audit <known-devices-file>; passive: reads only ip neigh's existing cache.
sa_lan_audit() {
    local known=${1:-} mac label line addr m unknown=0 seen="" first suffix=s
    [ -f "$known" ] || { echo "audit: known-devices file not found" >&2; return 64; }
    command -v ip >/dev/null 2>&1 || { echo "audit: ip command not found" >&2; return 2; }
    declare -A names=()
    while read -r mac label; do
        [[ -z ${mac:-} || $mac == \#* ]] && continue
        [[ $mac =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ && ${label:-} =~ ^[A-Za-z0-9\ _.-]+$ ]] || {
            echo "audit: bad known-devices line: $mac $label" >&2; return 64; }
        names[${mac,,}]=$label
    done < "$known"
    while read -r line; do
        addr="$(awk '{print $1}' <<<"$line")"
        m="$(awk '{for(i=1;i<NF;i++) if($i=="lladdr") print tolower($(i+1))}' <<<"$line")"
        [[ $m =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]] || continue
        first=$((16#${m%%:*}))
        [ $((first & 1)) -eq 0 ] || continue
        case " $seen " in *" $m "*) continue ;; esac
        seen="$seen $m"
        if [ -n "${names[$m]+x}" ]; then printf '%-40s %s  %s\n' "$addr" "$m" "${names[$m]}"
        else printf '%-40s %s  UNKNOWN\n' "$addr" "$m"; unknown=$((unknown + 1)); fi
    done < <(ip -o neigh show 2>/dev/null)
    if [ "$unknown" -gt 0 ]; then
        [ "$unknown" -eq 1 ] && suffix=""
        echo "audit: $unknown unknown device$suffix" >&2; return 3
    fi
    return 0
}
