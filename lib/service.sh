#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/service.sh -- service lifecycle. Written from master prompt v8 Part III.
# Needs lib/history.sh (sa_history_rollback) for reload_safe.
#
# ASSUMPTIONS (spec is silent; unmeasured design choices):
#   * a FAILED PRE-reload health check is treated like a failed post-check:
#     the snapshot is rolled back, the service restarted, health rechecked.
#     (Pre-check runs after the new config is written, so failure = bad config.)
#   * apply vs plan mode is SA_MODE (default "apply", i.e. fail closed);
#     SA_MODE=plan prints intended actions and touches nothing.
#   * after a successful rollback-and-recover, reload_safe returns 1 (the
#     requested change did NOT take effect); 99 only if still unhealthy.

sa_service_check() { systemctl is-active --quiet "$1"; }

sa_service_health() {
  case $1 in
    nginx)   nginx -t >/dev/null 2>&1 ;;
    php-fpm) php-fpm -t >/dev/null 2>&1 ;;
    mariadb|mysql) mysqladmin ping >/dev/null 2>&1 ;;
    *) echo "sa_service_health: unknown service $1" >&2; return 64 ;;
  esac
}

sa_service_reload() {
  if ! sa_service_check "$1" && [ "${SA_SERVICE_FORCE:-0}" != 1 ]; then
    echo "service $1 inactive: reload skipped"; return 0
  fi
  systemctl reload "$1"
}

sa_service_restart() { systemctl restart "$1"; }

sa_service_reload_safe() {  # <name> <snapshot-id>
  local name=${1:-} snap=${2:-}
  [ -n "$name" ] || { echo "reload_safe: service name required" >&2; return 64; }
  if [ "${SA_MODE:-apply}" = plan ]; then
    echo "plan: health($name) -> reload $name -> health($name); on failure rollback ${snap:-<id>}, restart, recheck"
    return 0
  fi
  if [ -z "$snap" ]; then
    echo "reload_safe: refusing without a snapshot id (fail closed)" >&2; return 2
  fi
  if ! sa_service_check "$name" && [ "${SA_SERVICE_FORCE:-0}" != 1 ]; then
    echo "service $name inactive: reload skipped"; return 0
  fi
  if sa_service_health "$name" && sa_service_reload "$name" && sa_service_health "$name"; then
    return 0
  fi
  echo "reload_safe: $name unhealthy, rolling back $snap" >&2
  sa_history_rollback "$snap" || echo "reload_safe: rollback command failed" >&2
  sa_service_restart "$name" || true
  if sa_service_health "$name"; then
    echo "reload_safe: $name healthy after rollback; change NOT applied" >&2
    return 1
  fi
  echo "CRITICAL: manual intervention required ($name unhealthy after rollback)" >&2
  exit 99
}
