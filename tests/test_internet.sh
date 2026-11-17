#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/config"
source "$ROOT/lib/internet.sh"
pass=0 fail=0
ok(){ pass=$((pass+1)); echo "ok   - $1"; }
bad(){ fail=$((fail+1)); echo "FAIL - $1"; }
out=$(sa_internet_plan both cloudflare cloudflare_tunnel tailscale example.com "" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"Access purpose: both"* ]] && [[ "$out" == *"no ports opened"* ]]; } && ok "combined public/private plan remains read-only" || bad "combined plan"
sa_internet_plan public cloudflare cloudflare_tunnel none bad_domain "" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "rejects malformed domain" || bad "domain validation"
sa_internet_plan public cloudflare direct none example.com 999.1.1.1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "rejects out-of-range IPv4" || bad "IPv4 validation"
sa_internet_plan nonsense none none none "" "" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "rejects unknown access purpose" || bad "purpose validation"

sa_internet_valid_ipv4 192.168.1.10 && bad "rejects private IPv4" || ok "rejects private IPv4"
sa_internet_valid_ipv4 127.0.0.1 && bad "rejects loopback IPv4" || ok "rejects loopback IPv4"
sa_internet_valid_ipv4 169.254.1.1 && bad "rejects link-local IPv4" || ok "rejects link-local IPv4"
sa_internet_valid_ipv4 010.0.0.1 && bad "rejects leading-zero IPv4" || ok "rejects leading-zero IPv4"


mkdir -p "$XDG_CONFIG_HOME/stackalign"
chmod 700 "$XDG_CONFIG_HOME/stackalign"
printf 'version=2\npurpose=both\ndns_provider=cloudflare\npublic_ingress=cloudflare_tunnel\nadmin_access=tailscale\ndomain=example.com\nserver_ipv4=\n' > "$XDG_CONFIG_HOME/stackalign/internet.conf"
chmod 600 "$XDG_CONFIG_HOME/stackalign/internet.conf"
out=$(sa_internet_show_saved_plan 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"Access purpose: both"* ]]; } && ok "loads valid owner-only saved config" || bad "valid saved config"
printf 'version=2\npurpose=both\npurpose=private\ndns_provider=cloudflare\npublic_ingress=cloudflare_tunnel\nadmin_access=tailscale\n' > "$XDG_CONFIG_HOME/stackalign/internet.conf"
chmod 600 "$XDG_CONFIG_HOME/stackalign/internet.conf"
sa_internet_show_saved_plan >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "rejects duplicate config keys" || bad "duplicate config key"
printf 'version=2\npurpose=both\ndns_provider=cloudflare\npublic_ingress=cloudflare_tunnel\nadmin_access=tailscale\n' > "$XDG_CONFIG_HOME/stackalign/internet-real"
chmod 600 "$XDG_CONFIG_HOME/stackalign/internet-real"
ln -sf internet-real "$XDG_CONFIG_HOME/stackalign/internet.conf"
sa_internet_show_saved_plan >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "rejects symlinked config file" || bad "symlink config"
rm -f "$XDG_CONFIG_HOME/stackalign/internet.conf"
printf 'version=2\npurpose=both\ndns_provider=cloudflare\npublic_ingress=cloudflare_tunnel\nadmin_access=tailscale\n' > "$XDG_CONFIG_HOME/stackalign/internet.conf"
chmod 644 "$XDG_CONFIG_HOME/stackalign/internet.conf"
sa_internet_show_saved_plan >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "rejects group/world-readable config" || bad "config permissions"
XDG_CONFIG_HOME=relative sa_internet_config_path >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "rejects relative XDG_CONFIG_HOME" || bad "relative XDG path"


out=$(sa_internet_plan both other cloudflare_tunnel tailscale example.com "" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"DNS action: MANUAL"* ]] && [[ "$out" == *"do not point an A record"* ]]; } && ok "Cloudflare Tunnel is not confused with direct-origin A records" || bad "tunnel DNS distinction"
out=$(sa_internet_plan public other direct none example.com 8.8.8.8 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"A record"* ]] && [[ "$out" == *"AAAA only after separately verifying"* ]]; } && ok "direct ingress plans A/AAAA to supplied public IP" || bad "direct DNS plan"
sa_internet_plan private none none tailscale "" "" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "private-only access does not require public DNS" || bad "private-only plan"

mkdir -p "$T/fakebin"
cat > "$T/fakebin/ip" <<'IP'
#!/usr/bin/env bash
case "$*" in
  "-brief address") echo "lo UNKNOWN 127.0.0.1/8"; exit "${FAKE_IP_ADDR_RC:-0}" ;;
  "route show default") [ "${FAKE_ROUTE_EMPTY:-0}" = 1 ] || echo "default via 192.0.2.1 dev eth0"; exit 0 ;;
esac
exit 2
IP
cat > "$T/fakebin/getent" <<'GETENT'
#!/usr/bin/env bash
[ "$1" = ahosts ] && [ "$2" = example.com ] || exit 2
[ "${FAKE_DNS_RC:-0}" = 0 ] || exit "$FAKE_DNS_RC"
echo "93.184.216.34 STREAM example.com"
GETENT
chmod +x "$T/fakebin/ip" "$T/fakebin/getent"
OLD_PATH=$PATH; PATH="$T/fakebin:$PATH"; export PATH
out=$(sa_internet_doctor 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"default via 192.0.2.1"* ]] && [[ "$out" == *"DNS example.com"* ]]; } && ok "doctor reports interface, route, and DNS success" || bad "doctor success path"
FAKE_IP_ADDR_RC=1 FAKE_DNS_RC=1; export FAKE_IP_ADDR_RC FAKE_DNS_RC
out=$(sa_internet_doctor 2>&1); rc=$?
{ [ "$rc" -ne 0 ] && [[ "$out" == *"interface inspection: FAILED"* ]] && [[ "$out" == *"DNS lookup example.com: FAILED"* ]]; } && ok "doctor propagates interface and DNS failures" || bad "doctor failure path"
unset FAKE_IP_ADDR_RC FAKE_DNS_RC
FAKE_ROUTE_EMPTY=1; export FAKE_ROUTE_EMPTY
out=$(sa_internet_doctor 2>&1); rc=$?
{ [ "$rc" -ne 0 ] && [[ "$out" == *"default route: MISSING"* ]]; } && ok "doctor detects missing default route" || bad "missing route detection"
unset FAKE_ROUTE_EMPTY
PATH=$OLD_PATH; export PATH
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
