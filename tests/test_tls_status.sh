#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_tls_status.sh -- read-only certificate status and issuance gate tests.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export SA_CERT_ROOT="$TMP/certs"
mkdir -p "$SA_CERT_ROOT"
chmod 700 "$SA_CERT_ROOT"

command -v openssl >/dev/null 2>&1 || { echo "FAIL: openssl is required for TLS status tests" >&2; exit 1; }

make_lineage() {
  local name=$1 san=$2 dir="$SA_CERT_ROOT/$1"
  mkdir -p "$dir"
  chmod 700 "$dir"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$dir/privkey.pem" -out "$dir/fullchain.pem" \
    -subj "/CN=$name" -addext "subjectAltName=DNS:$san" -days 2 >/dev/null 2>&1
  chmod 600 "$dir/privkey.pem"
  chmod 644 "$dir/fullchain.pem"
  printf 'lego\n' > "$dir/.client"
  chmod 600 "$dir/.client"
}

source "$ROOT/lib/tls.sh"
make_lineage "example.test" "example.test"
out=$(sa_tls_status "example.test")
printf '%s\n' "$out" | grep -q 'client: lego'
printf '%s\n' "$out" | grep -q 'certificate: NOT_EXPIRED'
printf '%s\n' "$out" | grep -q 'hostname: MATCH (example.test)'
printf '%s\n' "$out" | grep -q 'private_key: MATCH'
printf '%s\n' "$out" | grep -q 'renewal: DUE_WITHIN_30_DAYS'
cli_out=$(bash "$ROOT/bin/stackalign" tls status example.test)
printf '%s\n' "$cli_out" | grep -q 'private_key: MATCH'

# acme.sh is a valid explicit lineage owner, not an unknown marker.
printf 'acme.sh\n' > "$SA_CERT_ROOT/example.test/.client"
chmod 600 "$SA_CERT_ROOT/example.test/.client"
out=$(sa_tls_status "example.test")
printf '%s\n' "$out" | grep -q 'client: acme.sh'
printf 'lego\n' > "$SA_CERT_ROOT/example.test/.client"
chmod 600 "$SA_CERT_ROOT/example.test/.client"

# The reverse mapping for wildcard lineage names must preserve exactly one dot.
make_lineage "_wildcard_.wild.example.test" "*.wild.example.test"
out=$(sa_tls_status "*.wild.example.test")
printf '%s\n' "$out" | grep -q 'hostname: MATCH (stackalign-probe.wild.example.test)'

# A mismatched private key is reported and returns non-zero.
mkdir -m 700 "$TMP/other"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$TMP/other/other.key" >/dev/null 2>&1
chmod 600 "$TMP/other/other.key"
cp "$TMP/other/other.key" "$SA_CERT_ROOT/example.test/privkey.pem"
set +e
out=$(sa_tls_status "example.test" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ]
printf '%s\n' "$out" | grep -q 'private_key: MISMATCH'

# Symlinked roots and key files are rejected.
ln -s "$SA_CERT_ROOT" "$TMP/certs-link"
set +e
out=$(SA_CERT_ROOT="$TMP/certs-link" sa_tls_status 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ]
printf '%s\n' "$out" | grep -q 'symlinked certificate root'

rm -f "$SA_CERT_ROOT/example.test/privkey.pem"
ln -s "$TMP/other/other.key" "$SA_CERT_ROOT/example.test/privkey.pem"
set +e
out=$(sa_tls_status "example.test" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ]
printf '%s\n' "$out" | grep -q 'UNSAFE_SYMLINK'

# Issuance and renewal stay blocked; status is read-only.
set +e
bash "$ROOT/bin/stackalign" tls issue example.test --apply >"$TMP/issue.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -q 'BLOCKED' "$TMP/issue.out"

set +e
sa_tls_enable_renewal_timer >"$TMP/timer.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -q 'BLOCKED' "$TMP/timer.out"

set +e
sa_tls_issue example.test lego letsencrypt http-01 "$TMP" test@example.test nginx >"$TMP/issue-helper.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -q 'BLOCKED' "$TMP/issue-helper.out"

echo "TLS status tests: PASS"
