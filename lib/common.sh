#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/common.sh -- shared StackAlign logging helpers.

log() {
    printf 'stackalign: %s\n' "$*" >&2
}
