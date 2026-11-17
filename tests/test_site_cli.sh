#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_site_cli.sh -- site lifecycle CLI plan/apply routing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/nginx/conf.d" "$TMP/www" "$TMP/backups"
cat >"$TMP/bin/nginx" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = -t ] || exit 64
exit 0
EOF
cat >"$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in is-active) exit 0 ;; reload) exit 0 ;; *) exit 64 ;; esac
EOF
chmod 700 "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
plan=$(SA_SITE_NGINX_DIR="$TMP/nginx/conf.d" bash "$ROOT/bin/stackalign" site add example.test "$TMP/www")
[[ "$plan" == *"plan: create loopback-only static Nginx vhost"* ]]
[ ! -e "$TMP/nginx/conf.d/stackalign-site-example.test.conf" ]
SA_SITE_TESTING=1 SA_SITE_NGINX_DIR="$TMP/nginx/conf.d" bash "$ROOT/bin/stackalign" site add example.test "$TMP/www" --apply
[ -f "$TMP/nginx/conf.d/stackalign-site-example.test.conf" ]
remove_plan=$(SA_SITE_NGINX_DIR="$TMP/nginx/conf.d" bash "$ROOT/bin/stackalign" site remove example.test)
[[ "$remove_plan" == *"no changes made"* ]]
[ -f "$TMP/nginx/conf.d/stackalign-site-example.test.conf" ]
SA_SITE_TESTING=1 SA_SITE_NGINX_DIR="$TMP/nginx/conf.d" SA_SITE_BACKUP_DIR="$TMP/backups" bash "$ROOT/bin/stackalign" site remove example.test --apply
[ ! -e "$TMP/nginx/conf.d/stackalign-site-example.test.conf" ]
[ -d "$TMP/www" ]
set +e
SA_SITE_TESTING=1 SA_SITE_NGINX_DIR="$TMP/nginx/conf.d" bash "$ROOT/bin/stackalign" site isolate example.test >/dev/null 2>&1
isolate_rc=$?
set -e
[ "$isolate_rc" -eq 2 ]
echo 'site CLI tests: PASS'
