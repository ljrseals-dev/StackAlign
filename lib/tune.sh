#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# PROVISIONAL lib/tune.sh -- built from the SUMMARY in master prompt v8 Part II,
# NOT from docs/TUNING.md (which was not available). Where TUNING.md differs,
# TUNING.md wins and this file is wrong. Lean profile only; standard profile
# refuses with error=standard_not_implemented.
#
# Usage: bash lib/tune.sh <ram_mib> <swap_mib> <profile> [floor]
#   profile: lean | standard | auto
#   floor  : if given, also search the arithmetic floor (RAM from 0 upward,
#            swap held fixed) and print arithmetic_floor_mib=
#
# ASSUMPTION (unmeasured): per-child PHP-FPM cost = 32 MiB (SA_PHP_CHILD_MIB).
# Chosen because it reproduces the two lean outcomes pinned in the summary
# (512/no-swap -> 1,48 ; 512+512 swap -> 4,64). Not taken from TUNING.md.
set -euo pipefail

: "${SA_OS_MIB:=200}"
: "${SA_DB_BASE_MIB:=120}"
: "${SA_PHP_MASTER_MIB:=15}"
: "${SA_NGINX_MIB:=10}"
: "${SA_OPCACHE_MIB:=32}"
: "${SA_WORKER_MIB:=0}"
: "${SA_REDIS_MIB:=0}"
: "${SA_PHP_CHILD_MIB:=32}"

sa_tune_compute() {
  local ram=$1 swap=$2 profile=$3
  local cap=$(( ram / 4 )) half=$(( swap / 2 ))
  local extra=$(( half < cap ? half : cap ))
  local usable=$(( ram + extra ))
  local ceiling=$(( usable * 90 / 100 ))
  local reserve=$(( SA_OS_MIB + SA_DB_BASE_MIB + SA_PHP_MASTER_MIB + SA_NGINX_MIB \
                    + SA_OPCACHE_MIB + SA_WORKER_MIB + SA_REDIS_MIB ))
  if [ "$profile" = auto ]; then
    if [ "$ram" -ge 2048 ]; then profile=standard; else profile=lean; fi
  fi
  if [ "$profile" = standard ]; then
    echo "error=standard_not_implemented"; return 2
  fi
  local avail=$(( ceiling - reserve ))
  if [ "$avail" -le 0 ]; then echo "error=no_room_after_fixed"; return 2; fi
  local c b
  for c in 4 3 2 1; do
    for b in 64 48 32; do
      if [ $(( c * SA_PHP_CHILD_MIB + b )) -le "$avail" ]; then
        echo "profile=lean"
        echo "max_children=$c"
        echo "buffer_pool_mib=$b"
        echo "max_connections=$(( c * 2 + 0 + 5 ))"
        [ "$c" -eq 1 ] && echo "warning=concurrency_1"
        return 0
      fi
    done
  done
  echo "error=no_candidate_fits"; return 2
}

sa_tune_floor() {
  local swap=$1 profile=$2 r
  for (( r = 0; r <= 65536; r++ )); do
    if sa_tune_compute "$r" "$swap" "$profile" >/dev/null 2>&1; then
      echo "$r"; return 0
    fi
  done
  return 1
}

main() {
  [ $# -ge 3 ] || { echo "usage: tune.sh <ram> <swap> <profile> [floor]" >&2; exit 64; }
  sa_tune_compute "$1" "$2" "$3" || exit $?
  if [ "${4:-}" = floor ]; then
    echo "arithmetic_floor_mib=$(sa_tune_floor "$2" "$3")"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
