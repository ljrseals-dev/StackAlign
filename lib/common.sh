#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Shared logging and trusted command execution boundary.
. "$(dirname "${BASH_SOURCE[0]}")/exec.sh"
if ! declare -F log >/dev/null 2>&1; then
    log() { printf '[%s] %s\n' "$(/usr/bin/date +%T)" "$*" >&2; }
fi
