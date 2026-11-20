#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/lib/hosting.sh"
# Test-only output fixture; production uses the trusted absolute executor.
sa_exec_capture() {
  local tool=$1; shift
  [ "${1-}" = -- ] || return 64
  shift
  "$tool" "$@"
}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok(){ pass=$((pass+1)); echo "ok   - $1"; }
bad(){ fail=$((fail+1)); echo "FAIL - $1"; }

for mode in nginx apache hybrid; do
  out=$(sa_hosting_plan "$mode" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && [[ "$out" == *"No packages installed"* ]]; then
    ok "$mode plan is read-only"
  else bad "$mode plan"; fi
done
out=$(sa_hosting_plan apache)
[[ "$out" == *"httpd"* && "$out" == *"proxy_fcgi_module"* && "$out" == *"loopback"* ]] && ok "Apache plan declares package, PHP-FPM integration and private backend" || bad "Apache plan contract"
out=$(sa_hosting_plan hybrid)
[[ "$out" == *"127.0.0.1:8081"* && "$out" == *"never public"* ]] && ok "hybrid plan keeps Apache upstream private" || bad "hybrid private upstream"
out=$(sa_hosting_plan apache)
[[ "$out" == *"shared pool is not tenant isolation"* ]] && ok "Apache plan warns shared PHP-FPM pool is not isolation" || bad "shared pool warning"
sa_hosting_plan invalid >/dev/null 2>&1; [ $? -eq 64 ] && ok "unknown mode rejected" || bad "unknown mode rejected"
mkdir -p "$T/bin"
for tool in nginx php-fpm; do printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/$tool"; chmod +x "$T/bin/$tool"; done
cat > "$T/bin/httpd" <<'SH'
#!/usr/bin/env bash
printf '%s\n' ' proxy_module (shared)' ' proxy_fcgi_module (shared)' ' mpm_event_module (shared)'
SH
chmod +x "$T/bin/httpd"
PATH="$T/bin:$PATH" sa_hosting_doctor >"$T/doctor.out" 2>&1
{ [ $? -eq 0 ] && grep -q 'mpm_event_module present' "$T/doctor.out"; } && ok "doctor verifies required Apache modules" || bad "doctor module inspection"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
