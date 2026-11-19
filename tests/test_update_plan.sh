#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Update planning accepts only known component/version data and never executes it.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -m 700 "$T/bin"
export CALLS="$T/calls" PATH="$T/bin:$PATH"
for tool in rpm dnf; do
  printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "$CALLS"\n' "$tool" > "$T/bin/$tool"
  chmod 700 "$T/bin/$tool"
done
set +e
out=$(bash "$ROOT/bin/stackalign" update plan 'nginx;touch /tmp/pwned' 1.2.3 2>&1)
r1=$?
out2=$(bash "$ROOT/bin/stackalign" update plan nginx '$(id)' 2>&1)
r2=$?
set -e
[ "$r1" -eq 64 ] && [ "$r2" -eq 64 ]
[ ! -s "$CALLS" ]
[ ! -e /tmp/pwned ]
echo "update plan input validation tests: PASS"
