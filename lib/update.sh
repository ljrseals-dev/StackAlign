#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/update.sh -- package update apply boundary.
#
# Real-host DNF transactions, dependency effects, service recovery, and RPM
# rollback have not completed disposable-VM acceptance. Apply is deliberately
# blocked here as well as at the CLI boundary. Do not restore the previous
# implementation until those prerequisites are evidenced and reviewed.
#
# Exit code: 2 means the operation is intentionally blocked without changes.

# Real-host DNF transactions and RPM rollback remain unverified.
# Keep direct library callers behind the same fail-closed gate as the CLI.
sa_update_apply() {
    echo "update: APPLY BLOCKED — real-host DNF transactions and RPM rollback are NOT VERIFIED; no package or service changes made" >&2
    return 2
}
