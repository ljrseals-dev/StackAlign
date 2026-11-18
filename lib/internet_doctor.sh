#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# Read-only, bounded host connectivity diagnostics. No configuration changes.

_sa_inet_json_escape() {
  local s=$1
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

sa_internet_doctor() {
  local format=${1:-text} failures=0 warnings=0
  local ip4_route="" ip6_route="" addr="" dns4="" dns6="" code=""
  local -a names=(interface ipv4_route ipv6_route dns_ipv4 dns_ipv6 https_ipv4 https_ipv6 https_proxy captive_portal)
  local -A status=() message=()

  [[ $# -le 1 && ( $format == text || $format == --json ) ]] || {
    echo "usage: stackalign internet doctor [--json]" >&2; return 64;
  }

  _sa_inet_record() {
    local key=$1 state=$2 msg=$3
    status[$key]=$state; message[$key]=$msg
    case "$state" in FAIL) failures=$((failures+1));; WARN) warnings=$((warnings+1));; esac
  }

  if command -v ip >/dev/null 2>&1; then
    if addr=$(ip -brief address 2>&1) && printf '%s\n' "$addr" | awk "$1 != \"lo\" && $2 != \"DOWN\" { found=1 } END { exit !found }"; then
      _sa_inet_record interface PASS "$addr"
    else
      _sa_inet_record interface FAIL "ip address inspection failed: $addr"
    fi
    if ip4_route=$(ip -4 route show default 2>&1) && [[ -n $ip4_route ]]; then
      _sa_inet_record ipv4_route PASS "$ip4_route"
    else
      _sa_inet_record ipv4_route FAIL "${ip4_route:-no IPv4 default route}"
    fi
    if ip6_route=$(ip -6 route show default 2>&1) && [[ -n $ip6_route ]]; then
      _sa_inet_record ipv6_route PASS "$ip6_route"
    else
      _sa_inet_record ipv6_route WARN "${ip6_route:-no IPv6 default route}"
    fi
  else
    _sa_inet_record interface FAIL "iproute2 'ip' command is unavailable"
    _sa_inet_record ipv4_route WARN "not checked because ip is unavailable"
    _sa_inet_record ipv6_route WARN "not checked because ip is unavailable"
  fi

  if command -v getent >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    if dns4=$(timeout 8 getent ahostsv4 example.com 2>&1) && [[ -n $dns4 ]]; then
      _sa_inet_record dns_ipv4 PASS "system NSS resolver returned IPv4 addresses"
    else
      _sa_inet_record dns_ipv4 FAIL "system NSS IPv4 lookup failed or timed out"
    fi
    if dns6=$(timeout 8 getent ahostsv6 example.com 2>&1) && [[ -n $dns6 ]]; then
      _sa_inet_record dns_ipv6 PASS "system NSS resolver returned IPv6 addresses"
    else
      _sa_inet_record dns_ipv6 WARN "system NSS IPv6 lookup failed, timed out, or no AAAA record is available"
    fi
  else
    _sa_inet_record dns_ipv4 FAIL "getent and GNU timeout are required for bounded resolver checks"
    _sa_inet_record dns_ipv6 WARN "not checked"
  fi

  if command -v curl >/dev/null 2>&1; then
    if code=$(curl -4 --connect-timeout 5 --max-time 10 --max-redirs 0 --silent --show-error --output /dev/null --write-out '%{http_code}' https://example.com 2>/dev/null) && [[ $code =~ ^[0-9]{3}$ ]] && (( 10#$code >= 200 && 10#$code < 500 )); then
      _sa_inet_record https_ipv4 PASS "HTTPS/TLS connection succeeded (HTTP $code)"
    else
      _sa_inet_record https_ipv4 FAIL "IPv4 HTTPS/TLS request failed or timed out"
    fi
    if code=$(curl -6 --connect-timeout 5 --max-time 10 --max-redirs 0 --silent --show-error --output /dev/null --write-out '%{http_code}' https://example.com 2>/dev/null) && [[ $code =~ ^[0-9]{3}$ ]] && (( 10#$code >= 200 && 10#$code < 500 )); then
      _sa_inet_record https_ipv6 PASS "HTTPS/TLS connection succeeded (HTTP $code)"
    else
      _sa_inet_record https_ipv6 WARN "IPv6 HTTPS/TLS request failed, timed out, or IPv6 is unavailable"
    fi
    if [[ -n ${https_proxy:-}${HTTPS_PROXY:-}${all_proxy:-}${ALL_PROXY:-} ]]; then
      _sa_inet_record https_proxy WARN "proxy environment variable is set; curl may route through a proxy (value deliberately hidden)"
    else
      _sa_inet_record https_proxy PASS "no HTTPS/ALL proxy environment variable detected"
    fi
  else
    _sa_inet_record https_ipv4 FAIL "curl is unavailable; HTTPS/TLS not checked"
    _sa_inet_record https_ipv6 WARN "curl is unavailable; IPv6 HTTPS/TLS not checked"
    _sa_inet_record https_proxy WARN "curl is unavailable"
  fi

  # This endpoint is a heuristic only: 204 is expected; redirects/content can indicate a captive portal.
  if command -v curl >/dev/null 2>&1; then
    if code=$(curl --connect-timeout 3 --max-time 6 --max-redirs 0 --silent --output /dev/null --write-out '%{http_code}' http://connectivitycheck.gstatic.com/generate_204 2>/dev/null) && [[ $code == 204 ]]; then
      _sa_inet_record captive_portal PASS "connectivity-check endpoint returned HTTP 204"
    elif [[ $code =~ ^[0-9]{3}$ ]]; then
      _sa_inet_record captive_portal WARN "connectivity-check endpoint returned HTTP $code; captive portal or filtering is possible"
    else
      _sa_inet_record captive_portal WARN "connectivity-check endpoint unreachable; portal status is indeterminate"
    fi
  else
    _sa_inet_record captive_portal WARN "curl unavailable; portal status not checked"
  fi

  if [[ $format == --json ]]; then
    printf '{'
    local first=1 key
    for key in "${names[@]}"; do
      (( first )) || printf ','
      first=0
      printf '"%s":{"status":"%s","detail":"%s"}' "$key" "${status[$key]}" "$(_sa_inet_json_escape "${message[$key]}")"
    done
    printf ',"summary":{"failures":%d,"warnings":%d,"read_only":true}}\n' "$failures" "$warnings"
  else
    echo "internet doctor: read-only diagnostics; no network configuration changed"
    for key in "${names[@]}"; do
      printf '%-16s %-4s %s\n' "$key" "${status[$key]}" "${message[$key]}"
    done
    echo "Summary: $failures failure(s), $warnings warning(s)"
    echo "Note: IPv6 and captive-portal checks are advisory; ICMP is not used as a reachability prerequisite."
  fi
  (( failures == 0 )) || return 1
  return 0
}
