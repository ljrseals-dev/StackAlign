#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
#
# lib/service.sh -- service lifecycle. Written from master prompt v8 Part III.
# Needs lib/history.sh (sa_history_rollback) for reload_safe.
#
. "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/exec.sh"
. "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/validate.sh"

# ASSUMPTIONS (spec is silent; unmeasured design choices):
#   * a FAILED PRE-reload health check is treated like a failed post-check:
#     the snapshot is rolled back, the service restarted, health rechecked.
#     (Pre-check runs after the new config is written, so failure = bad config.)
#   * apply vs plan mode is SA_MODE (default "apply", i.e. fail closed);
#     SA_MODE=plan prints intended actions and touches nothing.
#   * after a successful rollback-and-recover, reload_safe returns 1 (the
#     requested change did NOT take effect); 99 only if still unhealthy.

_sa_service_name_ok() {
  sa_validate_service_name "${1-}"
}

sa_service_check() {
  _sa_service_name_ok "${1-}" || { echo "service: unsupported service name" >&2; return 64; }
  sa_exec systemctl -- is-active --quiet "$1"
}

sa_service_health() {
  case $1 in
    nginx)   sa_exec nginx -- -t >/dev/null 2>&1 && sa_service_check "$1" ;;
    php-fpm) sa_exec php-fpm -- -t >/dev/null 2>&1 && sa_service_check "$1" ;;
    mariadb|mysql) sa_exec mysqladmin -- ping >/dev/null 2>&1 && sa_service_check "$1" ;;
    *) echo "sa_service_health: unknown service $1" >&2; return 64 ;;
  esac
}

sa_service_reload() {
  _sa_service_name_ok "${1-}" || { echo "service: unsupported service name" >&2; return 64; }
  if ! sa_service_check "$1" && [ "${SA_SERVICE_FORCE:-0}" != 1 ]; then
    echo "service $1 inactive: reload skipped"; return 0
  fi
  sa_exec systemctl -- reload "$1"
}

sa_service_restart() { _sa_service_name_ok "${1-}" || return 64; sa_exec systemctl -- restart "$1"; }

sa_service_reload_safe() {  # <name> <snapshot-id>
  local name=${1:-} snap=${2:-}
  _sa_service_name_ok "$name" || { echo "reload_safe: unsupported service name" >&2; return 64; }
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
  if ! sa_history_rollback "$snap"; then
    echo "CRITICAL: rollback failed; manual intervention required ($name)" >&2
    exit 99
  fi
  if ! sa_service_restart "$name"; then
    echo "CRITICAL: restart failed after rollback; manual intervention required ($name)" >&2
    exit 99
  fi
  if sa_service_health "$name"; then
    echo "reload_safe: $name healthy after rollback; change NOT applied" >&2
    return 1
  fi
  echo "CRITICAL: manual intervention required ($name unhealthy after rollback)" >&2
  exit 99
}
