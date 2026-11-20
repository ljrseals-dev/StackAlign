#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# tests/test_tls_certbot_plan.sh -- plan-only Certbot HTTP-01 validation.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/webroot"
chmod 755 "$TMP/webroot"
cat > "$TMP/bin/certbot" <<'CERTBOT'
#!/bin/sh
printf 'executed\n' >> "$CERTBOT_EXECUTION_MARKER"
exit 99
CERTBOT
chmod 700 "$TMP/bin/certbot"
export CERTBOT_EXECUTION_MARKER="$TMP/certbot-was-executed"

source "$ROOT/lib/tls.sh"

# These tests isolate plan/status behavior; dedicated tests exercise clock failures.
sa_tls_clock_preflight() { printf '%s\n' 'clock: synchronized=yes timezone=Etc/UTC'; }
PATH="$TMP/bin:$PATH"
export PATH
export SA_CERT_ROOT="$TMP/stackalign-certs"
mkdir -m 700 "$SA_CERT_ROOT"

out=$(sa_tls_certbot_http01_plan example.com "$TMP/webroot" admin@example.com)
printf '%s\n' "$out" | grep -q '^state: PLAN_ONLY$'
printf '%s\n' "$out" | grep -q '^source_provenance: NOT_VERIFIED$'
printf '%s\n' "$out" | grep -q '^execution: NOT_RUN$'
printf '%s\n' "$out" | grep -q -- '--webroot-path'
printf '%s\n' "$out" | grep -q -- '--config-dir'
[ ! -e "$CERTBOT_EXECUTION_MARKER" ]

# Wildcard names must use DNS-01; Certbot HTTP-01 planning refuses them.
set +e
out=$(sa_tls_certbot_http01_plan '*.example.com' "$TMP/webroot" admin@example.com 2>&1)
rc=$?
set -e
[ "$rc" -eq 64 ]
printf '%s\n' "$out" | grep -q 'tls_http01_wildcard_requires_dns01'

# Reject path traversal, non-canonical paths, and symlinked webroots.
set +e
out=$(sa_tls_certbot_http01_plan example.com "$TMP/webroot/../webroot" admin@example.com 2>&1)
rc=$?
set -e
[ "$rc" -eq 64 ]
printf '%s\n' "$out" | grep -q 'tls_http01_webroot_invalid'

ln -s "$TMP/webroot" "$TMP/webroot-link"
set +e
out=$(sa_tls_certbot_http01_plan example.com "$TMP/webroot-link" admin@example.com 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ]
printf '%s\n' "$out" | grep -q 'tls_http01_webroot_unavailable'

set +e
out=$(sa_tls_certbot_http01_plan example.com "$TMP/webroot" 'admin@example.com;touch /tmp/should-not-exist' 2>&1)
rc=$?
set -e
[ "$rc" -eq 64 ]
printf '%s\n' "$out" | grep -q 'tls_contact_email_invalid'
[ ! -e /tmp/should-not-exist ]
[ ! -e "$CERTBOT_EXECUTION_MARKER" ]

# CLI parser rejects unapproved clients before any client discovery or execution.
set +e
cli=$(bash "$ROOT/bin/stackalign" tls plan-issue example.com --client lego --challenge http-01 --webroot "$TMP/webroot" --email admin@example.com 2>&1)
rc=$?
set -e
[ "$rc" -eq 64 ]
printf '%s\n' "$cli" | grep -q 'must be explicitly certbot'

# Issuance remains blocked even when the CLI is invoked with --apply.
set +e
cli=$(bash "$ROOT/bin/stackalign" tls issue example.com --apply 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ]
printf '%s\n' "$cli" | grep -q 'BLOCKED'

echo "TLS Certbot HTTP-01 plan tests: PASS"
