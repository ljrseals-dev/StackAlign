#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/update.sh -- transactional package update with RPM rollback.
# Needs: log, sa_history_snapshot <path> [slug], sa_cache_get,
#        sa_service_reload_safe <service> <snapshot-id>.
# Exit codes: 0 ok, 1 update failed and rolled back, 99 rollback failed or
#             service still unhealthy after config rollback.
#
# Two separate rollbacks:
#   * config/files : one sa_history_snapshot of the package's config path
#                    (default /etc/<package>, or the optional 4th argument),
#                    restored by sa_service_reload_safe on its own failure.
#   * RPM          : captured NEVRA + dnf -y downgrade.
#
# Contract adaptation: lib/service.sh exits (rather than returns) 99 when the
# service remains unhealthy after config rollback. Run it in a subshell to
# capture that status and still attempt the RPM downgrade.

# Real-host DNF transactions and RPM rollback remain unverified.
# Keep direct library callers behind the same fail-closed gate as the CLI.
sa_update_apply() {
    echo "update: APPLY BLOCKED — real-host DNF transactions and RPM rollback are NOT VERIFIED; no package or service changes made" >&2
    return 2
}
