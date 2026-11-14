#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/update.sh -- transactional package update with RPM rollback.
# Needs: log, sa_history_snapshot <path> [slug], sa_cache_get,
#        sa_service_health/sa_service_restart/sa_service_reload_safe (lib/service.sh).
# Exit codes: 0 ok, 1 update failed and rolled back, 99 rollback failed.
#
# Real-contract notes (lib/service.sh):
#   * sa_service_reload_safe <service> <snapshot-id> restores the CONFIG snapshot
#     itself on failure, and calls `exit 99` when the service is still unhealthy.
#     It runs in a subshell here so that exit 99 cannot skip the RPM rollback.
#   * After `dnf downgrade` the service is restarted and health-checked again,
#     because the running process may still be the new binary.

# Usage: sa_update_apply <package> <target_nevra> <service> [snapshot_path]
sa_update_apply() {
    local pkg="${1:?package}" target="${2:?target nevra}" svc="${3:?service}"
    local spath="${4:-/etc/$pkg}" old now snap slug rpm_path rc=0
    old="$(rpm -q --qf '%{NEVRA}' "$pkg")" || { log "update: $pkg not installed"; return 1; }

    # Also rejects services sa_service_health does not know (rc 64).
    sa_service_health "$svc" || { log "update: $svc is not healthy before the update; refusing"; return 1; }
    if [ ! -e "$spath" ]; then
        log "update: snapshot path $spath not found; pass it as the 4th argument"
        return 1
    fi
    slug="pre-update-${pkg//[^A-Za-z0-9_.-]/_}"
    snap="$(sa_history_snapshot "$spath" "$slug")" || { log "update: snapshot failed"; return 1; }
    [ -n "$snap" ] || { log "update: empty snapshot id"; return 1; }
    log "update: $pkg $old -> $target (snapshot $snap of $spath)"

    rpm_path="$(sa_cache_get "$target")" || { log "update: cannot fetch $target"; return 1; }

    if dnf -y install "$rpm_path"; then
        ( sa_service_reload_safe "$svc" "$snap" ) || rc=$?
        if [ "$rc" -eq 0 ]; then
            log "update: $pkg -> $target ok"
            return 0
        fi
        log "update: service check failed (rc=$rc), rolling back to $old"
    else
        now="$(rpm -q --qf '%{NEVRA}' "$pkg" 2>/dev/null)" || now=""
        if [ "$now" = "$old" ]; then
            log "update: dnf install failed; package unchanged"
            return 1
        fi
        log "update: dnf install failed part-way, rolling back to $old"
    fi

    if ! dnf -y downgrade "$old"; then
        log "update: ROLLBACK FAILED, manual repair needed ($old)"
        return 99
    fi
    if sa_service_restart "$svc" && sa_service_health "$svc"; then
        log "update: rolled back to $old"
        return 1
    fi
    log "update: $svc unhealthy after downgrade to $old; manual repair needed"
    return 99
}
