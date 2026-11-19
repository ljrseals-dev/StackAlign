#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/lib/exec.sh"
T=$(mktemp -d)
trap '/usr/bin/rm -rf -- "$T"' EXIT
mkdir -m 700 "$T/bin"
marker="$T/should-not-exist"
printf '#!/usr/bin/env bash\nexit 99\n' > "$T/bin/openssl"
chmod 700 "$T/bin/openssl"

# A poisoned PATH cannot replace the fixed executable path.
PATH="$T/bin"
export PATH
sa_exec openssl -- version >/dev/null

# Shell syntax in an argument remains data; it is never evaluated.
set +e
sa_exec openssl -- version '$(touch '"$marker"')' >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
[ ! -e "$marker" ]

# Unknown executable names and missing separators fail closed.
if sa_exec 'openssl;touch' -- version >/dev/null 2>&1; then
    echo "unexpectedly accepted an unapproved executable" >&2
    exit 1
fi
if sa_exec openssl version >/dev/null 2>&1; then
    echo "unexpectedly accepted missing argument separator" >&2
    exit 1
fi

echo "trusted executor: PASS"
