#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# Internet access planning and operator-input capture. No network, DNS,
# firewall, package, service, or tunnel changes are made by this module.

sa_internet_die() { echo "stackalign internet: $*" >&2; return 1; }

sa_internet_config_path() {
  local base=${XDG_CONFIG_HOME:-${HOME:-}/.config}
  printf '%s/stackalign/internet.conf\n' "$base"
}

sa_internet_valid_domain() {
  local d=$1
  [ ${#d} -le 253 ] || return 1
  [[ $d =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

sa_internet_valid_ipv4() {
  local ip=$1 a b c d
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<< "$ip"
  (( 10#$a <= 255 && 10#$b <= 255 && 10#$c <= 255 && 10#$d <= 255 ))
}

sa_internet_plan() {
  local purpose=${1:-both} provider=${2:-unknown} domain=${3:-} ip=${4:-}
  case "$purpose" in public|private|both) ;; *) sa_internet_die "purpose must be public, private, or both"; return 64 ;; esac
  case "$provider" in cloudflare|tailscale|wireguard|none|unknown) ;; *) sa_internet_die "provider must be cloudflare, tailscale, wireguard, none, or unknown"; return 64 ;; esac
  [ -z "$domain" ] || sa_internet_valid_domain "$domain" || { sa_internet_die "invalid domain name"; return 64; }
  [ -z "$ip" ] || sa_internet_valid_ipv4 "$ip" || { sa_internet_die "invalid IPv4 address"; return 64; }
  cat <<EOF
StackAlign internet access plan (read-only)
  Access purpose: $purpose
  DNS/tunnel provider: $provider
  Domain: ${domain:-NOT PROVIDED}
  Server IPv4: ${ip:-NOT PROVIDED}
EOF
  if [[ $purpose == public || $purpose == both ]]; then
    echo "  Public web: DNS A/AAAA and HTTPS required; verify authoritative DNS and reachability."
  fi
  if [[ $purpose == private || $purpose == both ]]; then
    echo "  Private administration: use a private overlay/VPN; do not publish SSH or database ports."
  fi
  case "$provider" in
    cloudflare) echo "  Tunnel direction: Cloudflare Tunnel for public web ingress; provider login/token and zone selection require operator authorization." ;;
    tailscale) echo "  Tunnel direction: Tailscale for private administration; device enrollment and ACL approval require operator action." ;;
    wireguard) echo "  Tunnel direction: WireGuard; keys, peer routing, endpoint reachability, and firewall policy require explicit configuration." ;;
    none) echo "  Tunnel direction: none selected; manual network/firewall configuration may be required." ;;
    unknown) echo "  Tunnel direction: UNKNOWN; StackAlign must ask the operator or provide manual provider-specific instructions." ;;
  esac
  cat <<'EOF'
  Automatic changes: NONE
  Credentials: no API tokens or private keys are requested or stored.
  Firewall: no ports opened; existing policy is not modified.
  DNS: no records changed.
  TLS: no certificates issued.
  Tunnel: no client installed, enrolled, or started.
  Status: PLAN ONLY — review and explicitly authorize a later apply workflow.
EOF
}

sa_internet_setup() {
  local purpose provider domain ip answer config dir tmp
  [[ -t 0 && -r /dev/tty ]] || { echo "internet setup requires an interactive terminal; no changes made" >&2; return 2; }
  printf '%s\n' "What should be reachable?" "  1) Public website" "  2) Private account/server administration" "  3) Both (recommended: separate public and private paths)" >&2
  printf 'Select 1-3: ' >&2
  IFS= read -r answer </dev/tty || return 2
  case "$answer" in 1) purpose=public ;; 2) purpose=private ;; 3) purpose=both ;; *) sa_internet_die "choose 1, 2, or 3"; return 64 ;; esac

  printf '%s\n' "Which provider do you use?" "  1) Cloudflare Tunnel (public web ingress)" "  2) Tailscale (private administration)" "  3) WireGuard (self-managed VPN)" "  4) None" "  5) I don't know (manual guidance)" >&2
  printf 'Select 1-5: ' >&2
  IFS= read -r answer </dev/tty || return 2
  case "$answer" in 1) provider=cloudflare ;; 2) provider=tailscale ;; 3) provider=wireguard ;; 4) provider=none ;; 5) provider=unknown ;; *) sa_internet_die "choose 1 through 5"; return 64 ;; esac

  printf 'Domain name (blank if not applicable/known): ' >&2
  IFS= read -r domain </dev/tty || return 2
  [ -z "$domain" ] || sa_internet_valid_domain "$domain" || { sa_internet_die "invalid domain; no settings saved"; return 64; }
  printf 'Server public IPv4 (blank if unknown): ' >&2
  IFS= read -r ip </dev/tty || return 2
  [ -z "$ip" ] || sa_internet_valid_ipv4 "$ip" || { sa_internet_die "invalid IPv4; no settings saved"; return 64; }

  config=$(sa_internet_config_path); dir=${config%/*}
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" || return 1
  umask 077
  tmp=$(mktemp "$dir/.internet.conf.XXXXXX") || return 1
  {
    printf 'version=1\n'
    printf 'purpose=%s\nprovider=%s\ndomain=%s\nserver_ipv4=%s\n' "$purpose" "$provider" "$domain" "$ip"
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$config" || { rm -f "$tmp"; return 1; }
  echo "Saved non-secret internet setup preferences to: $config"
  echo "No DNS, firewall, package, service, TLS, or tunnel changes were made."
  sa_internet_plan "$purpose" "$provider" "$domain" "$ip"
}

sa_internet_show_saved_plan() {
  local config; config=$(sa_internet_config_path)
  [ -f "$config" ] || { sa_internet_die "no saved setup; run: stackalign internet setup"; return 1; }
  local version="" purpose="" provider="" domain="" ip="" key value
  while IFS='=' read -r key value; do
    case "$key" in
      version) version=$value ;;
      purpose) purpose=$value ;;
      provider) provider=$value ;;
      domain) domain=$value ;;
      server_ipv4) ip=$value ;;
      *) sa_internet_die "unknown config key '$key'; refusing to use config"; return 1 ;;
    esac
  done < "$config"
  [ "$version" = 1 ] || { sa_internet_die "unsupported or missing config version"; return 1; }
  sa_internet_plan "$purpose" "$provider" "$domain" "$ip"
}

sa_internet_doctor() {
  local failures=0 cmd
  echo "internet doctor: read-only; no network configuration changed"
  for cmd in ip getent; do
    if command -v "$cmd" >/dev/null 2>&1; then echo "$cmd: available"; else echo "$cmd: MISSING"; failures=$((failures+1)); fi
  done
  if command -v ip >/dev/null 2>&1; then
    ip -brief address 2>&1 | sed 's/^/interface: /'
    ip route show default 2>&1 | sed 's/^/default-route: /'
  fi
  if command -v getent >/dev/null 2>&1; then
    echo "DNS resolver configuration:"
    getent ahosts localhost 2>&1 | sed 's/^/  /'
  fi
  echo "Provider authentication, authoritative DNS, external reachability, firewall/provider rules, and tunnel health require separate checks."
  return "$failures"
}
