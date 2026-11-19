#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Verify direct library callers cannot bypass the DNF rollback gate.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
mkdir -m 700 "$T/bin"
export SA_TEST_LOG="$T/commands.log"
export PATH="$T/bin:$PATH"

for cmd in rpm dnf systemctl; do
    cat > "$T/bin/$cmd" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "$SA_TEST_LOG"
exit 99
MOCK
    chmod 700 "$T/bin/$cmd"
done

source "$ROOT/lib/update.sh"
set +e
output=$(sa_update_apply 'nginx;touch /tmp/stackalign-pwned' 'bad target' 'nginx;id' '/tmp/../etc' 2>&1)
rc=$?
set -e

[ "$rc" -eq 2 ]
[[ "$output" == *"APPLY BLOCKED"* ]]
[ ! -s "$SA_TEST_LOG" ]
[ ! -e /tmp/stackalign-pwned ]

echo "update apply gate: PASS"
