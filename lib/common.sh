#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/common.sh -- minimal shared logger (new file; repo had no log()).
if ! declare -F log >/dev/null 2>&1; then
    log() { printf '[%s] %s\n' "$(date +%T)" "$*" >&2; }
fi
