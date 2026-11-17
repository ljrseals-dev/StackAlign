#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_site_lifecycle.sh -- admin-managed static Nginx vhost lifecycle.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/nginx/conf.d" "$T/www/example.test" "$T/www/second.test" "$T/backups"
cat >"$T/bin/nginx" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = -t ] || exit 64
printf 'nginx -t\n' >>"$SITE_TOOL_LOG"
[ "${FAKE_NGINX_RC:-0}" -eq 0 ]
EOF
cat >"$T/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$SITE_TOOL_LOG"
case "${1:-}" in
  is-active) [ "${FAKE_NGINX_ACTIVE:-1}" -eq 1 ] ;;
  reload) [ "${FAKE_RELOAD_RC:-0}" -eq 0 ] ;;
  *) exit 64 ;;
esac
EOF
chmod 700 "$T/bin/"*
export PATH="$T/bin:$PATH" SITE_TOOL_LOG="$T/tools.log"
export SA_SITE_TESTING=1 SA_SITE_NGINX_DIR="$T/nginx/conf.d" SA_SITE_BACKUP_DIR="$T/backups"
source "$ROOT/lib/site.sh"

# Plan mode never writes.
plan=$(sa_site_add example.test "$T/www/example.test" 0)
[[ "$plan" == *"loopback-only static Nginx vhost"* ]]
[[ ! -e "$SA_SITE_NGINX_DIR/stackalign-site-example.test.conf" ]]

# Strict hostname and canonical document-root validation.
set +e
sa_site_add '-bad.example' "$T/www/example.test" 1 >/dev/null 2>&1; bad_domain=$?
ln -s "$T/www/example.test" "$T/www/link"
sa_site_add link.example "$T/www/link" 1 >/dev/null 2>&1; symlink_root=$?
sa_site_add example.test "$T/www/../www/example.test" 1 >/dev/null 2>&1; dot_root=$?
set -e
[[ "$bad_domain" -eq 64 && "$symlink_root" -eq 64 && "$dot_root" -eq 64 ]]

# Apply creates a static-only, loopback vhost and reloads an active Nginx.
sa_site_add example.test "$T/www/example.test" 1
target="$SA_SITE_NGINX_DIR/stackalign-site-example.test.conf"
[[ -f "$target" && ! -L "$target" ]]
grep -Fq 'listen 127.0.0.1:8080;' "$target"
grep -Fq 'server_name example.test;' "$target"
grep -Fq "root $T/www/example.test;" "$target"
grep -Fq 'try_files $uri $uri/ =404;' "$target"
! grep -q 'fastcgi_pass' "$target"
grep -q '^systemctl reload nginx$' "$SITE_TOOL_LOG"

# Identical repeat is idempotent; foreign config is never overwritten.
before=$(sha256sum "$target")
sa_site_add example.test "$T/www/example.test" 1 | grep -q unchanged
after=$(sha256sum "$target")
[[ "$before" == "$after" ]]
printf 'operator config\n' >"$SA_SITE_NGINX_DIR/stackalign-site-foreign.test.conf"
set +e
sa_site_add foreign.test "$T/www/example.test" 1 >/dev/null 2>&1; foreign_rc=$?
set -e
[[ "$foreign_rc" -eq 1 ]]
[[ "$(cat "$SA_SITE_NGINX_DIR/stackalign-site-foreign.test.conf")" == 'operator config' ]]

# Baseline nginx -t failure leaves no generated file.
set +e
FAKE_NGINX_RC=1 sa_site_add second.test "$T/www/second.test" 1 >/dev/null 2>&1; bad_test_rc=$?
set -e
[[ "$bad_test_rc" -eq 1 && ! -e "$SA_SITE_NGINX_DIR/stackalign-site-second.test.conf" ]]

# Reload failure removes the newly-added config.
set +e
FAKE_RELOAD_RC=1 sa_site_add second.test "$T/www/second.test" 1 >/dev/null 2>&1; reload_add_rc=$?
set -e
[[ "$reload_add_rc" -eq 1 && ! -e "$SA_SITE_NGINX_DIR/stackalign-site-second.test.conf" ]]

# Removal is plan-only by default; apply archives config, never site data.
remove_plan=$(sa_site_remove example.test 0)
[[ "$remove_plan" == *"document root and site data will be preserved"* ]]
[[ -f "$target" ]]
sa_site_remove example.test 1
[[ ! -e "$target" && -d "$T/www/example.test" ]]
backup=$(find "$SA_SITE_BACKUP_DIR" -maxdepth 1 -type f -name 'example.test-*.conf' -print -quit)
[[ -n "$backup" && -f "$backup" ]]
[[ "$(stat -c %a "$backup")" == 600 ]]
[[ "$(stat -c %a "$SA_SITE_BACKUP_DIR")" == 700 ]]

# If reload fails during removal, the previous config is restored.
sa_site_add second.test "$T/www/second.test" 1
second="$SA_SITE_NGINX_DIR/stackalign-site-second.test.conf"
set +e
FAKE_RELOAD_RC=1 sa_site_remove second.test 1 >/dev/null 2>&1; reload_remove_rc=$?
set -e
[[ "$reload_remove_rc" -eq 1 && -f "$second" ]]
grep -q '^# Managed by StackAlign site lifecycle v1$' "$second"

# Remove refuses files not bearing StackAlign's ownership marker.
set +e
sa_site_remove foreign.test 1 >/dev/null 2>&1; unmanaged_rc=$?
set -e
[[ "$unmanaged_rc" -eq 1 && -f "$SA_SITE_NGINX_DIR/stackalign-site-foreign.test.conf" ]]

echo 'site lifecycle tests: PASS'
