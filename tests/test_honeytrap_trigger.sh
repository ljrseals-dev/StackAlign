#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr. (@ljrseals-dev)
# Repository: https://github.com/ljrseals-dev/StackAlign

set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin"
export PATH="$TMP/bin:$PATH"
export HONEYTRAP_SS_BIN=ss HONEYTRAP_PS_BIN=ps HONEYTRAP_LOGGER_BIN=logger

cat >"$TMP/bin/ss" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' 'ESTAB 0 0 10.0.0.2:22 8.8.8.8:53000 users:(("sshd",pid=123,fd=4))'
MOCK
cat >"$TMP/bin/ps" <<'MOCK'
#!/usr/bin/env bash
printf '1\n'
MOCK
cat >"$TMP/bin/logger" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HONEYTRAP_LOG"
MOCK
chmod +x "$TMP/bin/"*
export HONEYTRAP_LOG="$TMP/events.log"

test_correlated_public_peer_is_emitted() {
    printf '%s\n' 'type=SYSCALL msg=audit(1.2:3): arch=c000003e syscall=2 success=yes pid=123 ppid=1 key=stackalign_honeytrap' |
        bash "$ROOT/scripts/honeytrap-trigger.sh"
    grep -q 'CORRELATED pid=123 peer=8.8.8.8 HONEYTRAP_ACCESS' "$HONEYTRAP_LOG"
}
test_unmatched_event_does_not_emit_ban_signal() {
    : >"$HONEYTRAP_LOG"
    printf '%s\n' 'type=SYSCALL msg=audit(1.2:4): arch=c000003e syscall=2 success=yes pid=456 ppid=1 key=stackalign_honeytrap' |
        HONEYTRAP_SS_BIN=false bash "$ROOT/scripts/honeytrap-trigger.sh"
    grep -q 'UNATTRIBUTED pid=456' "$HONEYTRAP_LOG"
    ! grep -q 'HONEYTRAP_ACCESS' "$HONEYTRAP_LOG"
}
run() {
    local failed=0
    test_correlated_public_peer_is_emitted || { echo 'FAIL correlated public peer'; failed=1; }
    test_unmatched_event_does_not_emit_ban_signal || { echo 'FAIL unmatched event fail-closed'; failed=1; }
    [[ "$failed" -eq 0 ]] && echo 'Honey Trap trigger tests passed.'
    return "$failed"
}
run
