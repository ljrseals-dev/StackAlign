#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/etc/php-fpm.d" "$T/etc/nginx/conf.d" "$T/etc/my.cnf.d" "$T/web"
export PATH="$T/bin:$PATH" SA_LEMP_ETC_ROOT="$T/etc" SA_LEMP_WEB_ROOT="$T/web"
export LOG="$T/actions.log" FAKE_MARIADBD_RC=0
cat > "$T/etc/php-fpm.d/www.conf" <<'EOF'
user = apache
group = apache
listen = /run/php-fpm/www.sock
;listen.owner = nobody
;listen.group = nobody
;listen.mode = 0660
EOF
for tool in dnf systemctl php-fpm nginx mariadbd; do
  cat > "$T/bin/$tool" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$LOG"
case "$(basename "$0"):$1" in
  systemctl:is-active) exit 0 ;;
  nginx:-t) exit "${FAKE_NGINX_TEST_RC:-0}" ;;
  mariadbd:--validate-config) exit "${FAKE_MARIADBD_RC:-0}" ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$T/bin/$tool"
done
SA_LEMP_OS_RELEASE_FILE="$T/fake-os-release"
source "$ROOT/lib/lemp.sh"
[ "$SA_LEMP_OS_RELEASE_FILE" = /etc/os-release ] || { echo "FAIL: OS release path override accepted"; exit 1; }
_sa_lemp_path_policy >/dev/null 2>&1; policy_rc=$?
[ "$policy_rc" -ne 0 ] && echo "ok   production LEMP roots restricted" || { echo "FAIL production LEMP roots restricted"; exit 1; }
_sa_lemp_path_policy() { [ "$SA_LEMP_ETC_ROOT" = "$T/etc" ] && [[ "$SA_LEMP_WEB_ROOT" == "$T/"* ]]; }
# Legacy environment flag must not bypass root checks on non-root callers.
if [ "$EUID" -ne 0 ]; then
  SA_LEMP_TESTING=1 sa_lemp_host_check >/dev/null 2>&1
  rc=$?
  [ "$rc" -ne 0 ] || { echo "FAIL: SA_LEMP_TESTING bypassed host gate" >&2; exit 1; }
fi
# Fixture-only host check override; production has no environment bypass.
sa_lemp_host_check() { sa_lemp_web_root_valid; }
# Explicit fixture-only executor; production executor never consults PATH.
sa_exec() {
  local tool=$1
  shift
  if [ "${1-}" = --timeout ]; then shift 2; fi
  [ "${1-}" = -- ] && shift
  "$T/bin/$tool" "$@"
}
pass=0 fail=0
ok(){ pass=$((pass+1)); echo "ok   - $1"; }
bad(){ fail=$((fail+1)); echo "FAIL - $1"; }

plan=$(sa_lemp_plan 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$plan" == *"127.0.0.1:8080"* ]] && [[ "$plan" == *"MariaDB: TCP bound to 127.0.0.1"* ]] && [[ "$plan" == *"no changes made"* ]] && [ ! -s "$LOG" ]; } && ok "plan is loopback-only and makes no calls" || bad "plan behavior"

for bad_root in relative "$T/web|injected" "$T/web/../escape" "$T/web;worker_processes" "$T/web//duplicate" "$T/web/"; do
  SA_LEMP_WEB_ROOT="$bad_root" sa_lemp_plan >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 64 ] && ok "unsafe web root rejected: $bad_root" || bad "unsafe web root accepted: $bad_root (rc=$rc)"
done
mkdir -p "$T/external"
ln -s "$T/external" "$T/web-link"
SA_LEMP_WEB_ROOT="$T/web-link" sa_lemp_plan >/dev/null 2>&1
rc=$?
[ "$rc" -eq 64 ] && ok "web root resolving through a symlink is rejected" || bad "symlinked web root accepted (rc=$rc)"
rm -f "$T/web-link"
[ ! -s "$LOG" ] && ok "invalid web roots cause no package or service calls" || bad "invalid web root side effects"

# A pre-existing symlink must be rejected before DNF and must not be followed.
mkdir -p "$T/web/public"
printf '%s\n' 'outside sentinel' > "$T/outside.php"
ln -s "$T/outside.php" "$T/web/public/index.php"
sa_lemp_apply >"$T/symlink.out" 2>&1
rc=$?
{ [ "$rc" -eq 64 ] && [ "$(cat "$T/outside.php")" = "outside sentinel" ] && [ ! -s "$LOG" ]; } && ok "symlinked health page rejected without following or installing packages" || bad "symlinked health page was followed"
rm -f "$T/web/public/index.php"

# A symlinked public directory redirects writes even when index.php is not a
# symlink. Refuse it before DNF and leave the external sentinel untouched.
mkdir -p "$T/external"
printf '%s\n' 'external directory sentinel' > "$T/external/index.php"
rmdir "$T/web/public"
ln -s "$T/external" "$T/web/public"
sa_lemp_apply >"$T/public-dir-symlink.out" 2>&1
rc=$?
{ [ "$rc" -eq 64 ] && [ "$(cat "$T/external/index.php")" = "external directory sentinel" ] && [ ! -s "$LOG" ]; } && ok "symlinked public directory rejected before package installation" || bad "symlinked public directory was followed"
rm -f "$T/web/public"
mkdir -p "$T/web/public"

# A symlinked MariaDB policy target must be rejected before DNF.
printf '%s\n' 'outside database policy' > "$T/outside.cnf"
ln -s "$T/outside.cnf" "$T/etc/my.cnf.d/99-stackalign.cnf"
sa_lemp_apply >"$T/db-symlink.out" 2>&1
rc=$?
{ [ "$rc" -eq 64 ] && [ "$(cat "$T/outside.cnf")" = "outside database policy" ] && [ ! -s "$LOG" ]; } && ok "symlinked MariaDB policy rejected before package installation" || bad "symlinked MariaDB policy was followed"
rm -f "$T/etc/my.cnf.d/99-stackalign.cnf"

: > "$LOG"
sa_lemp_apply >"$T/apply.out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q 'dnf -y install -- nginx mariadb-server php-fpm php-mysqlnd' "$LOG"; } && ok "uses only EL repository package names" || bad "package installation"
grep -q '^user = nginx$' "$T/etc/php-fpm.d/www.conf" &&
grep -q '^group = nginx$' "$T/etc/php-fpm.d/www.conf" &&
grep -q '^listen.owner = nginx$' "$T/etc/php-fpm.d/www.conf" &&
grep -q '^listen.group = nginx$' "$T/etc/php-fpm.d/www.conf" &&
ok "PHP-FPM pool runs as nginx with matching socket ownership" || bad "PHP-FPM pool configuration"
grep -q 'listen 127.0.0.1:8080' "$T/etc/nginx/conf.d/stackalign.conf" &&
grep -q "root $T/web/public" "$T/etc/nginx/conf.d/stackalign.conf" &&
ok "Nginx binds loopback and uses configured document root" || bad "Nginx site configuration"
[ -f "$T/web/public/index.php" ] &&
grep -q 'StackAlign LEMP beta' "$T/web/public/index.php" &&
ok "PHP health page created" || bad "PHP health page"
grep -q 'php-fpm -t' "$LOG" && grep -q 'nginx -t' "$LOG" &&
grep -q 'systemctl enable --now mariadb' "$LOG" &&
grep -q 'systemctl enable --now php-fpm' "$LOG" &&
grep -q 'systemctl enable --now nginx' "$LOG" &&
ok "configuration tests and all service activation commands run" || bad "validation/service activation sequence"

# Verify MariaDB and Nginx hardening after a successful apply.
grep -q '^bind-address=127.0.0.1$' "$T/etc/my.cnf.d/99-stackalign.cnf" &&
grep -q '^local-infile=0$' "$T/etc/my.cnf.d/99-stackalign.cnf" &&
grep -q '^symbolic-links=0$' "$T/etc/my.cnf.d/99-stackalign.cnf" &&
ok "MariaDB TCP is loopback-only and risky features are disabled" || bad "MariaDB policy"
grep -q 'server_tokens off' "$T/etc/nginx/conf.d/stackalign.conf" &&
grep -q 'client_max_body_size 16m' "$T/etc/nginx/conf.d/stackalign.conf" &&
grep -Fq 'location ~ /\.(?!well-known/)' "$T/etc/nginx/conf.d/stackalign.conf" &&
ok "Nginx version disclosure, body size, and dotfile policy are hardened" || bad "Nginx hardening"

# A failed post-generation Nginx check must restore the prior health page.
printf '%s\n' 'operator-owned health page' > "$T/web/public/index.php"
FAKE_NGINX_TEST_RC=1 sa_lemp_apply >"$T/failure.out" 2>&1
rc=$?
{ [ "$rc" -ne 0 ] && [ "$(cat "$T/web/public/index.php")" = "operator-owned health page" ]; } && ok "failed config validation restores pre-existing health page" || bad "failed config validation did not restore health page"

# If the health page did not exist before apply, rollback must remove the new file.
rm -f "$T/web/public/index.php"
FAKE_NGINX_TEST_RC=1 sa_lemp_apply >"$T/failure-new.out" 2>&1
rc=$?
{ [ "$rc" -ne 0 ] && [ ! -e "$T/web/public/index.php" ]; } && ok "failed config validation removes newly created health page" || bad "failed config validation left new health page"

# MariaDB config-validation failure must restore all four managed files.
printf '%s\n' 'previous database policy' > "$T/etc/my.cnf.d/99-stackalign.cnf"
printf '%s\n' 'previous site' > "$T/etc/nginx/conf.d/stackalign.conf"
printf '%s\n' 'previous health page' > "$T/web/public/index.php"
printf '%s\n' 'user = apache' 'group = apache' 'listen = /run/php-fpm/www.sock' > "$T/etc/php-fpm.d/www.conf"
FAKE_MARIADBD_RC=1 sa_lemp_apply >"$T/mariadb-failure.out" 2>&1
rc=$?
{ [ "$rc" -ne 0 ] && [ "$(cat "$T/etc/my.cnf.d/99-stackalign.cnf")" = "previous database policy" ] && [ "$(cat "$T/etc/nginx/conf.d/stackalign.conf")" = "previous site" ] && [ "$(cat "$T/web/public/index.php")" = "previous health page" ] && grep -qx 'user = apache' "$T/etc/php-fpm.d/www.conf"; } && ok "MariaDB validation failure restores every managed file" || bad "MariaDB validation rollback"
FAKE_MARIADBD_RC=0

# A failed rollback must preserve the snapshot instead of deleting the
# only recovery copy. Override the restore helper to inject that failure.
sa_lemp_restore() { return 1; }
FAKE_NGINX_TEST_RC=1 sa_lemp_apply >"$T/restore-failure.out" 2>&1
rc=$?
backup=$(sed -n 's/.*backup preserved at \(.*\) for manual recovery/\1/p' "$T/restore-failure.out" | tail -n 1)
{ [ "$rc" -ne 0 ] && [ -n "$backup" ] && [ -d "$backup" ] && [ -f "$backup$T/etc/php-fpm.d/www.conf" ]; } && ok "incomplete rollback preserves recovery snapshot" || bad "incomplete rollback deleted recovery snapshot"
[ -z "$backup" ] || rm -rf -- "$backup"

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
