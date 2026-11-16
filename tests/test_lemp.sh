#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/etc/php-fpm.d" "$T/etc/nginx/conf.d" "$T/web"
export PATH="$T/bin:$PATH" SA_LEMP_TESTING=1 SA_LEMP_ETC_ROOT="$T/etc" SA_LEMP_WEB_ROOT="$T/web"
export LOG="$T/actions.log"
cat > "$T/etc/php-fpm.d/www.conf" <<'EOF'
user = apache
group = apache
listen = /run/php-fpm/www.sock
;listen.owner = nobody
;listen.group = nobody
;listen.mode = 0660
EOF
for tool in dnf systemctl php-fpm nginx; do
  cat > "$T/bin/$tool" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$LOG"
case "$(basename "$0"):$1" in
  systemctl:is-active) exit 0 ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$T/bin/$tool"
done
source "$ROOT/lib/lemp.sh"
pass=0 fail=0
ok(){ pass=$((pass+1)); echo "ok   - $1"; }
bad(){ fail=$((fail+1)); echo "FAIL - $1"; }

plan=$(sa_lemp_plan 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$plan" == *"127.0.0.1:8080"* ]] && [[ "$plan" == *"no changes made"* ]] && [ ! -s "$LOG" ]; } && ok "plan is loopback-only and makes no calls" || bad "plan behavior"

: > "$LOG"
sa_lemp_apply >"$T/apply.out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q 'dnf -y install nginx mariadb-server php-fpm php-mysqlnd' "$LOG"; } && ok "uses only EL repository package names" || bad "package installation"
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

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
