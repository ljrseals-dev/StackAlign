#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# CLI-level proof that update apply cannot execute unverified DNF operations.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -m 700 "$T/bin"
export CALLS="$T/calls" PATH="$T/bin:$PATH"
for tool in dnf rpm systemctl; do
  printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "$CALLS"\n' "$tool" > "$T/bin/$tool"
  chmod 700 "$T/bin/$tool"
done
set +e
out=$(bash "$ROOT/bin/stackalign" update apply nginx nginx-1.2.3-1.el9.x86_64 nginx 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ]
[[ "$out" == *"APPLY BLOCKED"* ]]
[ ! -s "$CALLS" ]
set +e
bash "$ROOT/bin/stackalign" update apply nginx >/dev/null 2>&1
bad_rc=$?
set -e
[ "$bad_rc" -eq 64 ]
echo "update CLI fail-closed tests: PASS"
