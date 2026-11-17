#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_site.sh -- isolated read-only site command tests.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/nginx" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -t ] && exit "${FAKE_NGINX_RC:-0}"
exit 64
EOF
cat > "$TMP/bin/httpd" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -t ] && exit "${FAKE_HTTPD_RC:-0}"
exit 64
EOF
chmod 700 "$TMP/bin/"*
PATH="$TMP/bin:$PATH"; export PATH
source "$ROOT/lib/site.sh"
sa_site_doctor nginx | grep -q 'nginx_config: valid'
sa_site_doctor apache | grep -q 'apache_config: valid'
if FAKE_NGINX_RC=1 sa_site_doctor nginx >/dev/null 2>&1; then echo 'FAIL: invalid nginx config reported valid' >&2; exit 1; fi
if sa_site_add example.com >/dev/null 2>&1; then echo 'FAIL: site add unexpectedly enabled' >&2; exit 1; fi
if sa_site_remove example.com >/dev/null 2>&1; then echo 'FAIL: site remove unexpectedly enabled' >&2; exit 1; fi
if sa_site_isolate example.com >/dev/null 2>&1; then echo 'FAIL: site isolate unexpectedly enabled' >&2; exit 1; fi
echo 'site helper tests: PASS'
