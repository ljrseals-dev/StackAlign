#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# StackAlign M2a memory tuner.
# Inputs are MiB unless otherwise stated. SA_* variables are explicit cost
# inputs; workload/role discovery is intentionally outside this arithmetic
# function and must supply effective values before calling it.
#
# Usage: tune.sh RAM_MIB SWAP_MIB lean|standard|auto [floor]
set -euo pipefail

SA_DB_BASE_MIB_EXPLICIT=0
[[ -v SA_DB_BASE_MIB ]] && SA_DB_BASE_MIB_EXPLICIT=1
: "${SA_OS_MIB:=200}"
: "${SA_DB_BASE_MIB:=120}"
: "${SA_PHP_MASTER_MIB:=15}"
: "${SA_NGINX_MIB:=10}"
: "${SA_OPCACHE_MIB:=32}"
: "${SA_SAFETY_MIB:=0}"
: "${SA_WORKER_MIB:=0}"
: "${SA_REDIS_SESSIONS_MIB:=0}"
: "${SA_REDIS_CACHE_MIB:=0}"
: "${SA_PHP_CHILD_MIB:=32}"
: "${SA_WORKER_DB_CONNECTIONS:=0}"
: "${SA_WORKLOAD:=generic_php}"
: "${SA_ROLE:=primary}"
: "${SA_MIN_RAM_MIB:=0}"
: "${SA_MIN_PROFILE:=lean}"

sa_is_uint() {
  [[ $1 =~ ^(0|[1-9][0-9]*)$ ]]
}

sa_validate_uint() {
  local name=$1 value=$2
  if ! sa_is_uint "$value"; then
    printf 'error=invalid_numeric_input\ninvalid_field=%s\n' "$name"
    return 2
  fi
  if (( value > 4294967295 )); then
    printf 'error=numeric_input_overflow\ninvalid_field=%s\n' "$name"
    return 2
  fi
}

sa_emit_reserve() {
  printf 'reserve_os_mib=%s\n' "$SA_OS_MIB"
  printf 'reserve_db_base_mib=%s\n' "$db_base_effective"
  printf 'reserve_php_master_mib=%s\n' "$SA_PHP_MASTER_MIB"
  printf 'reserve_nginx_mib=%s\n' "$SA_NGINX_MIB"
  printf 'reserve_opcache_mib=%s\n' "$SA_OPCACHE_MIB"
  printf 'reserve_safety_mib=%s\n' "$SA_SAFETY_MIB"
  printf 'reserve_worker_mib=%s\n' "$SA_WORKER_MIB"
  printf 'reserve_redis_sessions_mib=%s\n' "$SA_REDIS_SESSIONS_MIB"
  printf 'reserve_redis_cache_mib=%s\n' "$SA_REDIS_CACHE_MIB"
}

sa_tune_compute() {
  local ram=$1 swap=$2 requested_profile=$3
  local name value db_base_effective=$SA_DB_BASE_MIB
  if [[ $SA_ROLE == slave_web && $SA_DB_BASE_MIB_EXPLICIT == 0 ]]; then db_base_effective=0; fi
  case "$SA_WORKLOAD" in generic_php|wordpress|woocommerce|laravel|xcart_5_6) ;; *) printf "error=unknown_workload\\n"; return 2 ;; esac
  case "$SA_ROLE" in primary|slave_web) ;; *) printf "error=unknown_role\\n"; return 2 ;; esac
  sa_validate_uint min_ram_mib "$SA_MIN_RAM_MIB" || return $?
  case "$SA_MIN_PROFILE" in lean|standard) ;; *) printf "error=invalid_min_profile\\n"; return 2 ;; esac
  for name in ram_mib swap_mib os_mib db_base_mib php_master_mib nginx_mib opcache_mib safety_mib worker_mib redis_sessions_mib redis_cache_mib php_child_mib worker_db_connections; do
    case "$name" in
      ram_mib) value=$ram ;; swap_mib) value=$swap ;;
      os_mib) value=$SA_OS_MIB ;; db_base_mib) value=$db_base_effective ;;
      php_master_mib) value=$SA_PHP_MASTER_MIB ;; nginx_mib) value=$SA_NGINX_MIB ;;
      opcache_mib) value=$SA_OPCACHE_MIB ;; safety_mib) value=$SA_SAFETY_MIB ;;
      worker_mib) value=$SA_WORKER_MIB ;; redis_sessions_mib) value=$SA_REDIS_SESSIONS_MIB ;;
      redis_cache_mib) value=$SA_REDIS_CACHE_MIB ;; php_child_mib) value=$SA_PHP_CHILD_MIB ;;
      worker_db_connections) value=$SA_WORKER_DB_CONNECTIONS ;;
    esac
    sa_validate_uint "$name" "$value" || return $?
  done
  if (( SA_PHP_CHILD_MIB == 0 )); then
    printf 'error=invalid_child_rss\n'
    return 2
  fi

  local cap=$(( ram / 4 )) half=$(( swap / 2 ))
  local extra=$(( half < cap ? half : cap ))
  local usable=$(( ram + extra ))
  local ceiling=$(( usable * 90 / 100 ))
  local reserve=$(( SA_OS_MIB + db_base_effective + SA_PHP_MASTER_MIB + SA_NGINX_MIB + SA_OPCACHE_MIB + SA_SAFETY_MIB + SA_WORKER_MIB + SA_REDIS_SESSIONS_MIB + SA_REDIS_CACHE_MIB ))
  local remaining=$(( ceiling - reserve ))
  local profile=$requested_profile

  case "$profile" in
    auto) if (( ram >= 2048 )); then profile=standard; else profile=lean; fi ;;
    lean|standard) ;;
    *) printf 'error=unknown_profile\n'; return 2 ;;
  esac

  printf 'requested_profile=%s\n' "$requested_profile"
  printf 'profile=%s\n' "$profile"
  printf 'ram_mib=%s\nswap_mib=%s\nusable_mib=%s\nceiling_mib=%s\n' "$ram" "$swap" "$usable" "$ceiling"
  sa_emit_reserve
  printf 'reserve_mib=%s\nremaining_mib=%s\n' "$reserve" "$remaining"

  if (( ram < SA_MIN_RAM_MIB )); then printf "warning=advisory_ram\\n"; fi
  if [[ $profile == lean && $SA_MIN_PROFILE == standard ]]; then printf "warning=advisory_profile\\n"; fi

  if (( remaining <= 0 )); then
    printf 'error=no_room_after_fixed\n'
    return 2
  fi

  if [[ $profile == standard ]]; then
    local php_budget=$(( remaining * 40 / 100 ))
    local db_available=$(( remaining - php_budget ))
    local lower=128
    local upper=$(( db_available - 512 ))
    local raw_60=$(( db_available * 60 / 100 ))
    printf 'php_budget_mib=%s\ndb_available_mib=%s\nbuffer_pool_lower_mib=%s\nbuffer_pool_upper_mib=%s\nbuffer_pool_raw_60_mib=%s\n' "$php_budget" "$db_available" "$lower" "$upper" "$raw_60"
    if (( upper < lower )); then
      printf 'error=buffer_pool_no_valid_range\n'
      return 2
    fi
    local buffer_pool=$raw_60
    (( buffer_pool < lower )) && buffer_pool=$lower
    (( buffer_pool > upper )) && buffer_pool=$upper
    local max_children=$(( php_budget / SA_PHP_CHILD_MIB ))
    printf 'buffer_pool_mib=%s\nmax_children=%s\n' "$buffer_pool" "$max_children"
    if (( max_children < 1 )); then
      printf 'error=no_candidate_fits\n'
      return 2
    fi
    printf 'max_connections=%s\n' "$(( max_children * 2 + SA_WORKER_DB_CONNECTIONS + 5 ))"
    return 0
  fi

  local best_c=0 best_b=0 c b total
  for c in 1 2 3 4; do
    for b in 32 48 64; do
      total=$(( c * SA_PHP_CHILD_MIB + b ))
      if (( total <= remaining && (c > best_c || (c == best_c && b > best_b)) )); then
        best_c=$c
        best_b=$b
      fi
    done
  done
  if (( best_c == 0 )); then
    printf 'error=no_candidate_fits\n'
    return 2
  fi
  printf 'max_children=%s\nbuffer_pool_mib=%s\n' "$best_c" "$best_b"
  printf 'max_connections=%s\n' "$(( best_c * 2 + SA_WORKER_DB_CONNECTIONS + 5 ))"
  if (( best_c == 1 )); then printf 'warning=concurrency_1\n'; fi
}

sa_tune_floor() {
  local swap=$1 profile=$2 ram
  for (( ram=0; ram<=65536; ram++ )); do
    if sa_tune_compute "$ram" "$swap" "$profile" >/dev/null 2>&1; then
      printf '%s\n' "$ram"
      return 0
    fi
  done
  printf 'error=arithmetic_floor_not_found\n' >&2
  return 1
}

main() {
  if (( $# < 3 || $# > 4 )); then
    printf 'usage: tune.sh RAM_MIB SWAP_MIB lean|standard|auto [floor]\n' >&2
    exit 64
  fi
  sa_tune_compute "$1" "$2" "$3" || return $?
  if [[ ${4:-} == floor ]]; then
    printf 'arithmetic_floor_mib=%s\n' "$(sa_tune_floor "$2" "$3")"
  elif [[ -n ${4:-} ]]; then
    printf 'error=unknown_option\n' >&2
    return 64
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
