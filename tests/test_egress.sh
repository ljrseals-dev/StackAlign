#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_egress.sh -- mock-tool contract tests; no real kernel behavior is proven.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; : > "$T/calls"
export CALLS="$T/calls" PATH="$T/bin:$PATH"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2' want '$3')"; fail=1; fi; }
mkfake() { printf '%s\n' '#!/usr/bin/env bash' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
mkfake nft 'echo "nft $*" >> "$CALLS"; case "$1" in -c) exit "${FAKE_NFT_CHECK_RC:-0}";; -f) exit "${FAKE_NFT_LOAD_RC:-0}";; list) exit "${FAKE_NFT_LIST_RC:-1}";; delete) exit "${FAKE_NFT_DELETE_RC:-0}";; esac; exit 0'
mkfake systemd-run 'echo "systemd-run $*" >> "$CALLS"; exit "${FAKE_SDRUN_RC:-0}"'
mkfake systemctl 'echo "systemctl $*" >> "$CALLS"; case "$1" in is-active) [ "${FAKE_TIMER_ACTIVE:-0}" = 1 ] && exit 0; exit 3;; stop) exit "${FAKE_STOP_RC:-0}";; esac; exit 0'
mkfake logger 'echo "logger $*" >> "$CALLS"'
mkfake getent 'if [ "$1" = ahostsv4 ] && [ "$2" = updates.example.com ]; then printf "%s\n" "203.0.113.10 STREAM $2" "203.0.113.11 STREAM $2" "203.0.113.10 DGRAM $2"; fi; exit 0'
mkfake ip 'cat "$FAKE_NEIGH"'
. "$ROOT/lib/egress.sh"
has() { case "$R" in *"$1"*) return 0 ;; esac; return 1; }
calls_has() { grep -q -- "$1" "$CALLS"; }
line_of() { grep -n -- "$1" "$CALLS" | head -1 | cut -d: -f1; }

cat > "$T/allow" <<'A'
# studio allowlist
203.0.113.0/24 tcp 443 # inline comment

updates.example.com tcp 443
2001:db8::1 udp 123
nowhere.example.net tcp 443
A
R="$(sa_egress_render "$T/allow" "9.9.9.9,2620:fe::fe" "192.168.1.0/24,fd00:1::/64" 2>"$T/err")"; check "render ok" "$?" 0
has "policy drop"; check "default-drop output chain" "$?" 0
has 'oif "lo" accept'; check "loopback allowed" "$?" 0
has "ct state established,related accept"; check "established replies allowed" "$?" 0
has "ip daddr 9.9.9.9 udp dport 53 accept"; check "DNS restricted to IPv4 resolver" "$?" 0
has "ip6 daddr 2620:fe::fe tcp dport 53 accept"; check "DNS restricted to IPv6 resolver" "$?" 0
case "$R" in *$'\n'"    udp dport 53 accept"*|*$'\n'"    tcp dport 53 accept"*) check "no unconditional DNS" 1 0 ;; *) check "no unconditional DNS" 0 0 ;; esac
has "ip daddr 192.168.1.0/24 accept"; check "IPv4 LAN rule" "$?" 0
has "ip6 daddr fd00:1::/64 accept"; check "IPv6 LAN rule" "$?" 0
has "ip daddr 203.0.113.0/24 tcp dport 443 accept"; check "CIDR allowlist rule" "$?" 0
has "ip daddr 203.0.113.10 tcp dport 443 accept"; check "hostname first address" "$?" 0
has "ip daddr 203.0.113.11 tcp dport 443 accept"; check "hostname second address" "$?" 0
check "hostname addresses deduplicated" "$(printf '%s' "$R" | grep -c 'ip daddr 203.0.113.10 tcp dport 443')" 1
has "ip6 daddr 2001:db8::1 udp dport 123 accept"; check "IPv6 allowlist rule" "$?" 0
case "$R" in *nowhere*) check "unresolved host emits no rule" 1 0 ;; *) check "unresolved host emits no rule" 0 0 ;; esac
grep -q "could not resolve nowhere.example.net" "$T/err"; check "unresolved host warned" "$?" 0
has "icmpv6 type { nd-neighbor-solicit, nd-router-solicit,"; check "ICMPv6 ND egress control emitted" "$?" 0
has "mld2-listener-report"; check "MLDv2 report emitted" "$?" 0
has "packet-too-big"; check "IPv6 PMTU error emitted" "$?" 0
has "icmp type { destination-unreachable, time-exceeded, parameter-problem } accept"; check "ICMPv4 errors emitted" "$?" 0
has "ip6 daddr ff02::1:2 udp sport 546 udp dport 547 accept"; check "DHCPv6 client rule emitted" "$?" 0
case "$R" in *nd-router-advert*) check "inbound router advertisement not emitted" 1 0 ;; *) check "inbound router advertisement not emitted" 0 0 ;; esac
case "$R" in *echo-request*) check "no unrestricted ping rule" 1 0 ;; *) check "no unrestricted ping rule" 0 0 ;; esac
case "$R" in *"add table inet"*|*"delete table inet"*) check "render has no non-atomic table preamble" 1 0 ;; *) check "render has no non-atomic table preamble" 0 0 ;; esac

bad() { printf '%s\n' "$1" > "$T/bad"; sa_egress_render "$T/bad" 9.9.9.9 none >/dev/null 2>&1; check "reject: $1" "$?" 64; }
bad "1.2.3.4 icmp 80"; bad "1.2.3.4 tcp 0"; bad "1.2.3.4 tcp 70000"
bad "1.2.3.4; rm tcp 80"; bad "bad_host! tcp 443"; bad "1.2.3.4 tcp 443 extra"
bad "300.1.1.1 tcp 443"; bad "1.2.3.4/33 tcp 443"; bad "1.2.3.999 tcp 443"
bad "010.0.0.1 tcp 443"; bad "08.0.0.1 tcp 443"; bad "1.02.3.4 tcp 443"
bad "0.0.0.0/0 tcp 443"; bad "::/0 tcp 443"; bad "0::/0 udp 53"
printf '%s\n' "0.0.0.0/0 tcp 443" > "$T/any"
SA_EGRESS_ALLOW_ANY=1 sa_egress_render "$T/any" 9.9.9.9 none >/dev/null 2>&1; check "/0 explicit override" "$?" 0
sa_egress_render "$T/allow" 9.9.9.9 "0.0.0.0/0" >/dev/null 2>&1; check "LAN /0 refused" "$?" 64
sa_egress_render "$T/allow" "" none >/dev/null 2>&1; check "missing DNS refused" "$?" 64
sa_egress_render "$T/allow" dns.example.com none >/dev/null 2>&1; check "DNS hostname refused" "$?" 64
sa_egress_render "$T/allow" 9.9.9.0/24 none >/dev/null 2>&1; check "DNS CIDR refused" "$?" 64
sa_egress_render "$T/allow" 9.9.9.9 "192.168.1.0/24,bad" >/dev/null 2>&1; check "bad LAN item refused" "$?" 64
printf '%s\n' "1.2.3.4 tcp 443" "bad line now" > "$T/half"
out="$(sa_egress_render "$T/half" 9.9.9.9 none 2>/dev/null)"; check "invalid file emits no partial ruleset" "$out" ""
SA_EGRESS_TABLE='bad;name' sa_egress_render "$T/allow" 9.9.9.9 none >/dev/null 2>&1; check "unsafe table identifier refused" "$?" 64

: > "$CALLS"; sa_egress_apply "$T/allow" 9.9.9.9 none >/dev/null 2>&1; check "apply without timer" "$?" 0
[ "$(line_of '^nft -c -f')" -lt "$(line_of '^nft -f')" ]; check "nft check precedes load" "$?" 0
calls_has systemd-run; check "no timer by default" "$?" 1
calls_has "logger -t stackalign-egress -- loaded table=stackalign_egress revert_seconds=0"; check "apply audited to syslog" "$?" 0

: > "$CALLS"; export FAKE_NFT_CHECK_RC=1
sa_egress_apply "$T/allow" 9.9.9.9 none 60 >/dev/null 2>&1; check "nft check failure returns 1" "$?" 1
calls_has '^nft -f'; check "check failure never loads" "$?" 1
calls_has systemd-run; check "check failure schedules no timer" "$?" 1
unset FAKE_NFT_CHECK_RC

: > "$CALLS"; sa_egress_apply "$T/allow" 9.9.9.9 none 120 >/dev/null 2>&1; check "apply with timer" "$?" 0
calls_has 'systemd-run --quiet --replace --unit=stackalign-egress-revert --on-active=120s'; check "revert timer uses replace" "$?" 0
[ "$(line_of '^systemd-run')" -lt "$(line_of '^nft -f')" ]; check "timer scheduled before load" "$?" 0
: > "$CALLS"; export FAKE_SDRUN_RC=1
sa_egress_apply "$T/allow" 9.9.9.9 none 120 >/dev/null 2>"$T/err"; check "timer scheduling failure returns 1" "$?" 1
calls_has '^nft -f'; check "timer failure never loads rules" "$?" 1
grep -q "NOTHING was loaded" "$T/err"; check "timer failure accurately reported" "$?" 0
unset FAKE_SDRUN_RC

: > "$CALLS"; export FAKE_TIMER_ACTIVE=1
sa_egress_apply "$T/allow" 9.9.9.9 none >/dev/null 2>&1; check "apply without new timer" "$?" 0
calls_has "systemctl stop stackalign-egress-revert.timer"; check "stale timer cancelled even when secs=0" "$?" 0
[ "$(line_of 'systemctl stop stackalign-egress-revert.timer')" -lt "$(line_of '^nft -f')" ]; check "stale timer cancelled before new load" "$?" 0
: > "$CALLS"; export FAKE_STOP_RC=1
sa_egress_apply "$T/allow" 9.9.9.9 none >/dev/null 2>&1; check "stale timer cancel failure refuses apply" "$?" 1
calls_has '^nft -f'; check "cancel failure prevents load" "$?" 1
unset FAKE_STOP_RC FAKE_TIMER_ACTIVE

: > "$CALLS"; export FAKE_NFT_LIST_RC=0
sa_egress_apply "$T/allow" 9.9.9.9 none >/dev/null 2>&1; check "existing table can be atomically replaced" "$?" 0
grep -q '^nft -c -f' "$CALLS"; check "replacement is checked" "$?" 0
# The first nft -c input includes a delete of our table; no other table is targeted.
unset FAKE_NFT_LIST_RC

cat > "$T/known" <<'K'
# known devices
AA:BB:CC:DD:EE:01 Studio_PC
aa:bb:cc:dd:ee:02 Audio_interface
K
cat > "$T/neigh" <<'N'
192.168.1.10 dev eth0 lladdr aa:bb:cc:dd:ee:01 REACHABLE
192.168.1.11 dev eth0 lladdr AA:BB:CC:DD:EE:02 STALE
192.168.1.99 dev eth0 FAILED
fe80::1 dev eth0 lladdr aa:bb:cc:dd:ee:01 router REACHABLE
ff02::1 dev eth0 lladdr 33:33:00:00:00:01 NOARP
224.0.0.251 dev eth0 lladdr 01:00:5e:00:00:fb PERMANENT
N
export FAKE_NEIGH="$T/neigh"; out="$(sa_lan_audit "$T/known" 2>/dev/null)"; check "known neighbours => rc 0" "$?" 0
case "$out" in *Studio_PC*Audio_interface*) check "known labels shown" 0 0 ;; *) check "known labels shown" 1 0 ;; esac
case "$out" in *33:33*|*01:00:5e*) check "multicast MACs skipped" 1 0 ;; *) check "multicast MACs skipped" 0 0 ;; esac
check "same MAC deduplicated across IPv4/IPv6" "$(printf '%s\n' "$out" | grep -c 'aa:bb:cc:dd:ee:01')" 1
printf '%s\n' "192.168.1.50 dev eth0 lladdr de:ad:be:ef:00:01 REACHABLE" "192.168.1.51 dev eth0 lladdr de:ad:be:ef:00:01 STALE" > "$T/neigh_bad"
FAKE_NEIGH="$T/neigh_bad" sa_lan_audit "$T/known" >/dev/null 2>"$T/err"; check "unknown MAC returns 3" "$?" 3
grep -q "audit: 1 unknown device$" "$T/err"; check "unknown device singularized" "$?" 0
printf '%s\n' "not-a-mac Thing" > "$T/known_bad"; sa_lan_audit "$T/known_bad" >/dev/null 2>&1; check "malformed known file => 64" "$?" 64
printf '%s\n' "aa:bb:cc:dd:ee:03 bad;label" > "$T/known_bad"; sa_lan_audit "$T/known_bad" >/dev/null 2>&1; check "unsafe label => 64" "$?" 64
sa_lan_audit "$T/missing" >/dev/null 2>&1; check "missing known file => 64" "$?" 64
exit "$fail"
