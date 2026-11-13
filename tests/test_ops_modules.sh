#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_ops_modules.sh -- focused validation tests for operational modules.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
export SA_AUDIT_QUEUE="$T/audit/queue.jsonl"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/extensions.sh"
. "$ROOT/lib/firewall.sh"
. "$ROOT/lib/security.sh"
. "$ROOT/lib/backup.sh"
. "$ROOT/lib/tls.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected '$2', got '$1')"; }

assert_eq "$(_sa_ext_pkg redis)" "php-pecl-redis" "redis allowlist"
_sa_ext_pkg unknown >/dev/null 2>&1 && fail "unknown extension accepted"

sa_fw_validate nftables none 2222 off || fail "valid firewall config rejected"
sa_fw_validate nftables none 65536 off >/dev/null 2>&1 && fail "out-of-range SSH port accepted"
sa_fw_refuse_ftp vsftpd || fail "FTP daemon was not refused"
fw="$(sa_fw_render_nft 2222 on)" || fail "nft rules did not render"
[[ $fw == *'meta l4proto ipv6-icmp accept'* ]] || fail "IPv6 ICMP rule missing"
[[ $fw == *'tcp dport 2222 accept'* ]] || fail "configured SSH port missing"
[[ $fw == *'udp dport 443 accept'* ]] || fail "HTTP/3 rule missing"

escaped="$(_sa_sec_esc $'quote" slash\\ newline\n')"
assert_eq "$escaped" 'quote\" slash\\ newline\n' "JSON string escaping"

_sa_bk_dir_ok "$T/backups" || fail "valid backup path rejected"
_sa_bk_dir_ok relative/path && fail "relative backup path accepted"
_sa_bk_dir_ok "$T/../escape" && fail "parent traversal accepted"

_sa_tls_domain_ok example.com || fail "ordinary domain rejected"
_sa_tls_domain_ok '*.example.com' || fail "wildcard domain rejected"
_sa_tls_domain_ok '-bad.example.com' && fail "invalid domain accepted"
assert_eq "$(_sa_tls_lineage '*.example.com')" "_wildcard_.example.com" "wildcard lineage"

echo "test_ops_modules: ok"
