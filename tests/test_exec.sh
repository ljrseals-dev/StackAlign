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

PATH="$T/bin"
export PATH
sa_exec openssl -- version >/dev/null

set +e
sa_exec openssl -- version '$(touch '"$marker"')' >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
[ ! -e "$marker" ]

if sa_exec 'openssl;touch' -- version >/dev/null 2>&1; then exit 1; fi
if sa_exec openssl version >/dev/null 2>&1; then exit 1; fi
if _sa_exec_binary bash >/dev/null 2>&1; then exit 1; fi

redacted=$(_sa_exec_redact <<'EOF'
password=hunter2 token:abc123 Authorization:BearerSecret https://user:pass@example.test/x
EOF
)
[[ $redacted == *'password=[REDACTED]'* ]]
[[ $redacted == *'token:[REDACTED]'* ]]
[[ $redacted == *'Authorization:[REDACTED]'* ]]
[[ $redacted == *'https://[REDACTED]@example.test/x'* ]]

echo "trusted executor: PASS"
