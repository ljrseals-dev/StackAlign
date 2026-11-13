#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/update.sh -- transactional package update with RPM rollback.
# Needs: log, sa_history_snapshot <path> [slug], sa_cache_get,
#        sa_service_reload_safe <service> <snapshot-id>.
# Exit codes: 0 ok, 1 update failed and rolled back, 99 rollback failed.
#
# Two separate rollbacks:
#   * config/files : one sa_history_snapshot of the package's config path
#                    (default /etc/<package>, or the optional 4th argument),
#                    restored by sa_service_reload_safe on its own failure.
#   * RPM          : captured NEVRA + `dnf -y downgrade`.

# Usage: sa_update_apply <package> <target_nevra> <service> [snapshot_path]
sa_update_apply() {
    local pkg="${1:?package}" target="${2:?target nevra}" svc="${3:?service}"
    local spath="${4:-/etc/$pkg}" old snap rpm_path
    old="$(rpm -q --qf '%{NEVRA}' "$pkg")" || { log "update: $pkg not installed"; return 1; }

    if [ ! -e "$spath" ]; then
        log "update: snapshot path $spath not found; pass it as the 4th argument"
        return 1
    fi
    snap="$(sa_history_snapshot "$spath" "pre-update-$pkg")" || { log "update: snapshot failed"; return 1; }
    [ -n "$snap" ] || { log "update: empty snapshot id"; return 1; }
    log "update: $pkg $old -> $target (snapshot $snap of $spath)"

    rpm_path="$(sa_cache_get "$target")" || { log "update: cannot fetch $target"; return 1; }

    if dnf -y install "$rpm_path" && sa_service_reload_safe "$svc" "$snap"; then
        log "update: $pkg -> $target ok"
        return 0
    fi

    log "update: failed, rolling back to $old"
    if dnf -y downgrade "$old"; then
        log "update: rolled back to $old"
        return 1
    fi
    log "update: ROLLBACK FAILED, manual repair needed ($old)"
    return 99
}
