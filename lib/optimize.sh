#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# M3 performance planner. This module is intentionally plan-only: it delegates
# all memory arithmetic to lib/tune.sh and performs no host mutation.

sa_optimize_plan() { # <standard|super>
  [ "$#" -eq 1 ] || { echo "usage: sa_optimize_plan <standard|super>" >&2; return 64; }
  local mode=$1
  case "$mode" in standard|super) ;; *) echo "optimize: invalid mode: $mode" >&2; return 64 ;; esac

  local meminfo=${SA_MEMINFO_PATH:-/proc/meminfo}
  local ram swap tune_script tune_out rc
  [ -r "$meminfo" ] || { echo "optimize: cannot read memory facts: $meminfo" >&2; return 1; }
  ram=$(awk '$1 == "MemTotal:" { print int($2 / 1024); found=1 } END { if (!found) exit 1 }' "$meminfo") || {
    echo "optimize: MemTotal missing or invalid" >&2; return 1;
  }
  swap=$(awk '$1 == "SwapTotal:" { print int($2 / 1024); found=1 } END { if (!found) exit 1 }' "$meminfo") || {
    echo "optimize: SwapTotal missing or invalid" >&2; return 1;
  }
  [[ $ram =~ ^[0-9]+$ && $swap =~ ^[0-9]+$ ]] || {
    echo "optimize: invalid memory facts" >&2; return 1;
  }

  tune_script=${SA_TUNE_SCRIPT:-${SA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/tune.sh}
  [ -r "$tune_script" ] || { echo "optimize: tuner not found: $tune_script" >&2; return 1; }
  if tune_out=$(bash "$tune_script" "$ram" "$swap" auto); then
    :
  else
    rc=$?
    printf '%s\n' "$tune_out"
    echo "optimize: tuner refused this host (exit $rc); no changes made" >&2
    return "$rc"
  fi

  local max_children buffer_pool max_connections profile
  max_children=$(printf '%s\n' "$tune_out" | awk -F= '$1=="max_children" {print $2; n++} END {if(n!=1) exit 1}') || {
    echo "optimize: tuner output missing or duplicates max_children" >&2; return 1;
  }
  buffer_pool=$(printf '%s\n' "$tune_out" | awk -F= '$1=="buffer_pool_mib" {print $2; n++} END {if(n!=1) exit 1}') || {
    echo "optimize: tuner output missing or duplicates buffer_pool_mib" >&2; return 1;
  }
  max_connections=$(printf '%s\n' "$tune_out" | awk -F= '$1=="max_connections" {print $2; n++} END {if(n!=1) exit 1}') || {
    echo "optimize: tuner output missing or duplicates max_connections" >&2; return 1;
  }
  profile=$(printf '%s\n' "$tune_out" | awk -F= '$1=="profile" {print $2; n++} END {if(n!=1) exit 1}') || {
    echo "optimize: tuner output missing or duplicates profile" >&2; return 1;
  }
  for value in "$max_children" "$buffer_pool" "$max_connections"; do
    [[ $value =~ ^[1-9][0-9]*$ ]] || { echo "optimize: invalid numeric tuner output" >&2; return 1; }
  done

  printf 'optimization_mode=%s\n' "$mode"
  printf 'tuner_profile=%s\n' "$profile"
  printf 'ram_mib=%s\nswap_mib=%s\n' "$ram" "$swap"
  printf 'max_children=%s\nbuffer_pool_mib=%s\nmax_connections=%s\n' "$max_children" "$buffer_pool" "$max_connections"
  printf 'action=plan_only\n'
  if [ "$mode" = super ]; then
    printf 'php_fpm_policy=static_candidate_requires_measured_worker_rss\n'
    printf 'mariadb_flush_policy=explicit_durability_acknowledgement_required\n'
  else
    printf 'php_fpm_policy=dynamic_candidate\n'
    printf 'mariadb_flush_policy=durable_default\n'
  fi
  printf 'note=no_files_written_no_packages_installed_no_services_restarted\n'
}
