#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/vm_egress_smoke.sh -- REAL-HOST smoke test for lib/egress.sh. NOT run by `make test`.
#
# Run ONLY on a disposable VM (IPv6 enabled if you want the IPv6 steps), as root, from the
# VM's CONSOLE, never over SSH. Takes about 4 minutes. It loads real nftables rules, so
# outbound traffic is blocked for up to a minute at a time. Every step has a revert timer and
# the script removes its table on exit.
#
#   sudo I_AM_ON_A_DISPOSABLE_VM=1 bash tests/vm_egress_smoke.sh
#   bash tests/vm_egress_smoke.sh --dry-run        # prints the plan, touches nothing
#
# Optional: EGRESS_TEST_V4_ADDR (default 1.1.1.1), EGRESS_TEST_V6_ADDR (default 2606:4700:4700::1111),
#           EGRESS_TEST_DNS (default 9.9.9.9), EGRESS_VM_ALLOW_SSH=1 (not recommended).
# Reachability probe = TCP connect to port 443 with a 6 s timeout.
#
# What it answers (the things the mock suite cannot): does this nft accept the ruleset; is
# outbound really blocked; does IPv6 work once an address is allowlisted (neighbour discovery);
# does the revert fire; does re-applying replace the old timer; does a scheduling failure
# leave NOTHING loaded.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V4="${EGRESS_TEST_V4_ADDR:-1.1.1.1}"; V6="${EGRESS_TEST_V6_ADDR:-2606:4700:4700::1111}"
DNS="${EGRESS_TEST_DNS:-9.9.9.9}"; OTHER4="${EGRESS_TEST_OTHER_ADDR:-8.8.8.8}"
# Pin the unit and table names: an inherited environment override must not make the timer
# checks or the cleanup act on a different unit or table than the module under test.
UNIT="stackalign-egress-revert"
export SA_EGRESS_REVERT_UNIT="$UNIT" SA_EGRESS_TABLE="stackalign_egress"

if [ "${1:-}" = "--dry-run" ]; then
    cat <<PLAN
Plan (nothing is executed in --dry-run):
  S0  baseline: $V4 reachable; IPv6 route present? ($V6 reachable)
  S1  rendered ruleset passes the real 'nft -c' on this machine
  S2  apply an EMPTY allowlist, revert 60s: table loaded, $V4 and $V6 blocked
  S3  wait 65s: revert fired, table gone, $V4 and $V6 reachable again
  S4  allowlist $V4 + $V6 (tcp 443), revert 60s: both reachable (IPv6 => neighbour discovery
      works), $OTHER4 blocked; confirm keeps the rules after the timer window
  S5  re-apply replaces the timer: apply 60s, apply 120s 10s later, table still loaded after
      65s, one timer active; confirm cancels it; remove deletes the table
  S6  systemd-run failure: apply returns 1 and NOTHING is loaded
PLAN
    exit 0
fi

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 2; }
[ "${I_AM_ON_A_DISPOSABLE_VM:-0}" = 1 ] || { echo "refusing: set I_AM_ON_A_DISPOSABLE_VM=1 (this loads real firewall rules)"; exit 2; }
if [ -n "${SSH_CONNECTION:-}" ] && [ "${EGRESS_VM_ALLOW_SSH:-0}" != 1 ]; then echo "refusing: run from the VM console, not over SSH"; exit 2; fi
for c in nft systemd-run systemctl timeout; do command -v "$c" >/dev/null 2>&1 || { echo "missing tool: $c"; exit 2; }; done

. "$ROOT/lib/egress.sh"
W="$(mktemp -d)"
cleanup() { sa_egress_remove >/dev/null 2>&1; systemctl stop "$UNIT.timer" >/dev/null 2>&1; rm -rf "$W"; }
trap cleanup EXIT

pass=0; failn=0; skip=0
ok()   { pass=$((pass+1)); echo "PASS  $1"; }
bad()  { failn=$((failn+1)); echo "FAIL  $1"; }
skp()  { skip=$((skip+1)); echo "SKIP  $1"; }
reach() { timeout 6 bash -c "exec 3<>/dev/tcp/$1/443" 2>/dev/null; }
loaded() { nft list table inet "$SA_EGRESS_TABLE" >/dev/null 2>&1; }
HAVE6=0; ip -6 route show default 2>/dev/null | grep -q . && HAVE6=1
: > "$W/empty"; printf '%s tcp 443\n%s tcp 443\n' "$V4" "$V6" > "$W/allow"

echo "== S0 baseline"
reach "$V4" && ok "S0 $V4 reachable before any rules" || { bad "S0 $V4 not reachable; fix the VM network first"; exit 1; }
if [ $HAVE6 -eq 1 ]; then reach "$V6" && ok "S0 $V6 reachable" || { skp "S0 IPv6 route exists but $V6 unreachable: IPv6 steps skipped"; HAVE6=0; }
else skp "S0 no IPv6 default route: IPv6 steps skipped"; fi

echo "== S1 real nft -c on the rendered ruleset"
sa_egress_render "$W/allow" "$DNS" none > "$W/r.nft" 2>"$W/err" && nft -c -f "$W/r.nft" 2>"$W/err" && ok "S1 ruleset accepted by this nft" || { bad "S1 nft rejected the ruleset: $(head -3 "$W/err")"; }

echo "== S2 empty allowlist blocks outbound (60s revert armed)"
sa_egress_apply "$W/empty" "$DNS" none 60 >/dev/null 2>&1 && ok "S2 apply returned 0" || bad "S2 apply failed"
loaded && ok "S2 table loaded" || bad "S2 table not loaded"
reach "$V4" && bad "S2 $V4 still reachable (default-deny not working)" || ok "S2 $V4 blocked"
[ $HAVE6 -eq 1 ] && { reach "$V6" && bad "S2 $V6 still reachable" || ok "S2 $V6 blocked"; }

echo "== S3 revert fires (waiting 65s)"
sleep 65
loaded && bad "S3 table still loaded after the revert window" || ok "S3 table removed by the revert timer"
reach "$V4" && ok "S3 $V4 reachable again" || bad "S3 $V4 still blocked after revert"
[ $HAVE6 -eq 1 ] && { reach "$V6" && ok "S3 $V6 reachable again" || bad "S3 $V6 still blocked after revert"; }

echo "== S4 allowlist works; IPv6 neighbour discovery works"
sa_egress_apply "$W/allow" "$DNS" none 60 >/dev/null 2>&1 && ok "S4 apply returned 0" || bad "S4 apply failed"
reach "$V4" && ok "S4 allowlisted $V4 reachable" || bad "S4 allowlisted $V4 blocked"
[ $HAVE6 -eq 1 ] && { reach "$V6" && ok "S4 allowlisted $V6 reachable (ICMPv6 ND rules work)" || bad "S4 allowlisted $V6 blocked (check the ICMPv6 rules)"; }
reach "$OTHER4" && bad "S4 non-allowlisted $OTHER4 reachable" || ok "S4 non-allowlisted $OTHER4 blocked"
sa_egress_confirm >/dev/null 2>&1 && ok "S4 confirm returned 0" || bad "S4 confirm failed"
sleep 65
loaded && ok "S4 rules still loaded after the old window (timer cancelled)" || bad "S4 rules vanished: confirm did not cancel the timer"
sa_egress_remove >/dev/null 2>&1; loaded && bad "S4 remove left the table" || ok "S4 remove deleted the table"

echo "== S5 re-apply replaces the revert timer"
if sa_egress_apply "$W/allow" "$DNS" none 60 >/dev/null 2>&1; then ok "S5 first apply (60s) returned 0"
else bad "S5 first apply failed; the replace test below would be meaningless"; fi
sleep 10
sa_egress_apply "$W/allow" "$DNS" none 120 >/dev/null 2>&1 && ok "S5 second apply (120s) returned 0" || bad "S5 second apply failed"
sleep 65
loaded && ok "S5 table still loaded after the FIRST timer's window (old timer replaced)" || bad "S5 first timer fired: --replace did not work"
systemctl is-active --quiet "$UNIT.timer" && ok "S5 one revert timer still pending" || bad "S5 no pending timer"
sa_egress_confirm >/dev/null 2>&1; systemctl is-active --quiet "$UNIT.timer" && bad "S5 timer still active after confirm" || ok "S5 confirm cancelled the timer"
sa_egress_remove >/dev/null 2>&1; loaded && bad "S5 table remains" || ok "S5 table removed"

echo "== S6 timer cannot be scheduled => NOTHING loaded"
mkdir -p "$W/fail"; printf '#!/bin/sh\nexit 1\n' > "$W/fail/systemd-run"; chmod +x "$W/fail/systemd-run"
PATH="$W/fail:$PATH" sa_egress_apply "$W/allow" "$DNS" none 60 >/dev/null 2>&1; rc=$?
[ $rc -eq 1 ] && ok "S6 apply returned 1" || bad "S6 apply returned $rc (wanted 1)"
loaded && bad "S6 rules were loaded without a safety net" || ok "S6 nothing loaded"

echo; echo "passed=$pass failed=$failn skipped=$skip"
[ $failn -eq 0 ]
