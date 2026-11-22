#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr. (@ljrseals-dev)
# Repository: https://github.com/ljrseals-dev/StackAlign
# Shared logging and trusted command execution boundary.
. "$(dirname "${BASH_SOURCE[0]}")/exec.sh"
if ! declare -F log >/dev/null 2>&1; then
    log() { printf '[%s] %s\n' "$(/usr/bin/date +%T)" "$*" >&2; }
fi
