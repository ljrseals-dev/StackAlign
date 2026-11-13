#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# T36: update plan is read-only with respect to StackAlign state.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export FAKE_LOG="$T/calls.log" FAKE_DNF_TARGET="nginx-1.2.3-1.el9.x86_64"
mkdir -p "$T/bin"
cat > "$T/bin/rpm" <<'EOF'
#!/usr/bin/env bash
echo "rpm $*" >> "$FAKE_LOG"
case "$*" in
  *'%{NEVRA}'*nginx*) printf '%s\\n' 'nginx-1.2.2-1.el9.x86_64'; exit 0 ;;
  *) exit 1 ;;
esac
EOF
cat > "$T/bin/dnf" <<'EOF'
#!/usr/bin/env bash
echo "dnf $*" >> "$FAKE_LOG"
case " $* " in
  *" --cacheonly "*" repoquery "*) printf '%s\\n' "$FAKE_DNF_TARGET"; exit 0 ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
export SA_HISTORY_ROOT="$T/history" SA_CONF_PATH="$T/stackalign.conf"
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }

out=$(bash "$ROOT/bin/stackalign" update plan nginx 1.2.3 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == *"Current: nginx-1.2.2-1.el9.x86_64"* ]] && [[ "$out" == *"Target:  nginx-1.2.3-1.el9.x86_64"* ]] && [[ "$out" == *"no StackAlign changes made"* ]]; then
  ok "plan resolves and displays exact current/target NEVRA"
else
  bad "plan output/exit status (rc=$rc): $out"
fi

if grep -q -- '--cacheonly' "$FAKE_LOG" && grep -q -- 'logfile=/dev/null' "$FAKE_LOG"; then
  ok "repoquery uses cached metadata and disables persistent DNF logfile"
else
  bad "repoquery read-only safeguards missing"
fi

if [ ! -e "$SA_HISTORY_ROOT" ] && [ ! -e "$T/vendor" ] && [ ! -e "$SA_CONF_PATH" ]; then
  ok "plan creates no snapshot, cache, or config state"
else
  bad "plan created persistent state"
fi

if [[ "$out" == *"would snapshot these configuration paths"* ]] && [[ "$out" == *"/etc/nginx"* ]] && [[ "$out" == *"service restart is expected"* ]] && [[ "$out" == *"environment-dependent"* ]]; then
  ok "plan declares config scope and downtime uncertainty"
else
  bad "plan omits config/downtime disclosure"
fi

if [[ "$out" == *"NOT VERIFIED"* ]] && [[ "$out" == *"does not authorize apply"* ]]; then
  ok "empty/unparsed tested matrix fails visibly as unverified"
else
  bad "tested-matrix uncertainty not disclosed"
fi

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
