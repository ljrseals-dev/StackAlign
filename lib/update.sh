#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/update.sh -- guarded package update boundary.
#
# Real-host DNF transactions and RPM rollback have not been acceptance-tested.
# Keep this lower-level entry point blocked as well as the CLI boundary: callers
# that source this library directly must not be able to bypass the gate.
#
# Re-enable only after disposable-VM acceptance tests cover transaction
# previews, dependency changes, package provenance, config snapshots,
# service health, interrupted transactions, and recovery from failed rollback.

sa_update_apply() {
    echo "update: APPLY BLOCKED — real-host DNF transactions and RPM rollback are NOT VERIFIED; no package or service changes made" >&2
    return 2
}
