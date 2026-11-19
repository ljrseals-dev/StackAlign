#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# The unverified real-host DNF apply/rollback boundary must stay blocked.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -m 700 "$T/bin"
export CALLS="$T/calls" PATH="$T/bin:$PATH"
for tool in dnf rpm systemctl; do
  printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "$CALLS"\n' "$tool" > "$T/bin/$tool"
  chmod 700 "$T/bin/$tool"
done
source "$ROOT/lib/update.sh"
set +e
out=$(sa_update_apply 'nginx;touch /tmp/stackalign-update-pwned' '$(id)' 'nginx' '/etc/nginx' 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ]
[[ "$out" == *"APPLY BLOCKED"* ]]
[ ! -s "$CALLS" ]
[ ! -e /tmp/stackalign-update-pwned ]
echo "update apply fail-closed tests: PASS"
