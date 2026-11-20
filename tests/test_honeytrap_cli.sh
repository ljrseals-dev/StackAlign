#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr. (@ljrseals-dev)
# Repository: https://github.com/ljrseals-dev/StackAlign

set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CLI="$ROOT/bin/stackalign"
help="$("$CLI" help honeytrap)"
grep -q 'install|status|remove|credentials' <<<"$help"
grep -q 'automatic bans disabled by default' <<<"$help"

guidance="$("$CLI" honeytrap credentials)"
grep -q 'No Honey Trap password' <<<"$guidance"
grep -q 'DECOY marker' <<<"$guidance"
grep -q 'SHA-256 is an integrity pin' <<<"$guidance"
grep -q 'Automatic IP bans are OFF by default' <<<"$guidance"
! grep -Eq 'BEGIN (OPENSSH|RSA|EC) PRIVATE KEY' <<<"$guidance"

echo "PASS Honey Trap CLI help and credential guidance"
