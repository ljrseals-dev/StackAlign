#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/lib/optimize.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }

mkdir -p "$T"
cat > "$T/meminfo" <<'EOF'
MemTotal:       2097152 kB
SwapTotal:            0 kB
EOF
export SA_MEMINFO_PATH="$T/meminfo" SA_TUNE_SCRIPT="$ROOT/lib/tune.sh"
export SA_OS_MIB=200 SA_DB_BASE_MIB=120 SA_PHP_MASTER_MIB=15 SA_NGINX_MIB=10
export SA_OPCACHE_MIB=32 SA_PHP_CHILD_MIB=32 SA_WORKLOAD=generic_php SA_ROLE=primary
out=$(sa_optimize_plan standard 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"optimization_mode=standard"* ]] && [[ "$out" == *"action=plan_only"* ]] && [[ "$out" == *"php_fpm_policy=dynamic_candidate"* ]]; } && ok "standard plan delegates to tuner" || bad "standard plan delegates to tuner"

out=$(sa_optimize_plan super 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"optimization_mode=super"* ]] && [[ "$out" == *"static_candidate_requires_measured_worker_rss"* ]] && [[ "$out" == *"durability_acknowledgement_required"* ]]; } && ok "super plan remains explicit and gated" || bad "super plan remains explicit and gated"

before=$(find "$T" -type f -printf '%p %s\n' | sort)
sa_optimize_plan standard >/dev/null 2>&1
after=$(find "$T" -type f -printf '%p %s\n' | sort)
[ "$before" = "$after" ] && ok "planning writes no files" || bad "planning writes no files"

sed -i 's/SwapTotal:.*/SwapTotal:             0 kB/' "$T/meminfo"
printf 'MemTotal: 262144 kB\n' > "$T/meminfo"
out=$(sa_optimize_plan standard 2>&1); rc=$?
{ [ "$rc" -ne 0 ] && [[ "$out" == *"no changes made"* ]]; } && ok "tuner refusal is propagated" || bad "tuner refusal is propagated"

sa_optimize_plan invalid >/dev/null 2>&1; [ "$?" -eq 64 ] && ok "invalid mode rejected" || bad "invalid mode rejected"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
