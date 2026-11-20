#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# tests/test_site.sh -- isolated read-only site command tests.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/emptybin" "$TMP/etc/nginx/conf.d" "$TMP/etc/nginx/sites-enabled" "$TMP/etc/httpd/conf.d" "$TMP/etc/httpd/sites-enabled" "$TMP/etc/nginx/conf.d/nested"
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
printf 'server {}\n' > "$TMP/etc/nginx/conf.d/site.conf"
printf 'server {}\n' > "$TMP/etc/httpd/conf.d/apache.conf"
ln -s ../conf.d/site.conf "$TMP/etc/nginx/sites-enabled/site.conf"
printf 'nested {}\n' > "$TMP/etc/nginx/conf.d/nested/ignored.conf"
PATH="$TMP/bin:$PATH"; export PATH
source "$ROOT/lib/site.sh"
# Fixture-only executor and binary discovery; production uses absolute paths.
sa_exec() {
  local tool=$1
  shift
  [ "${1-}" = -- ] && shift
  "$TMP/bin/$tool" "$@"
}
_sa_site_has_binary() { [ -x "$TMP/bin/$1" ]; }
sa_site_doctor nginx | grep -q 'nginx_config: valid'
sa_site_doctor apache | grep -q 'apache_config: valid'
hash -r
if ( _sa_site_has_binary() { return 1; }; sa_site_doctor all >/dev/null 2>&1 ); then echo 'FAIL: doctor succeeded without checking a server' >&2; exit 1; fi
hash -r
if FAKE_NGINX_RC=1 sa_site_doctor nginx >/dev/null 2>&1; then echo 'FAIL: invalid nginx config reported valid' >&2; exit 1; fi
inventory=$(SA_SITE_ETC_ROOT="$TMP/etc" sa_site_list)
grep -Fq "$TMP/etc/nginx/conf.d/site.conf" <<<"$inventory"
grep -Fq "$TMP/etc/nginx/sites-enabled/site.conf"$'\t''../conf.d/site.conf' <<<"$inventory"
grep -Fq "$TMP/etc/httpd/conf.d/apache.conf" <<<"$inventory"
if grep -Fq 'ignored.conf' <<<"$inventory"; then echo 'FAIL: nested file included in top-level inventory' >&2; exit 1; fi
empty=$(SA_SITE_ETC_ROOT="$TMP/empty" sa_site_list)
grep -q 'no vhost configuration files found' <<<"$empty"
if sa_site_add example.com >/dev/null 2>&1; then echo 'FAIL: site add unexpectedly enabled' >&2; exit 1; fi
if sa_site_remove example.com >/dev/null 2>&1; then echo 'FAIL: site remove unexpectedly enabled' >&2; exit 1; fi
if sa_site_isolate example.com >/dev/null 2>&1; then echo 'FAIL: site isolate unexpectedly enabled' >&2; exit 1; fi
echo 'site helper tests: PASS'
