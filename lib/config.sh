#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/config.sh -- INI parser. Written from master prompt v8 Part III.
# Parsed as data: never sourced, never eval'd.
#
# ASSUMPTIONS (the spec is silent; unmeasured design choices):
#   * one pair of surrounding double quotes around a value is stripped
#   * no inline-comment stripping (a '#' mid-line is part of the value)
# NOT IMPLEMENTED: the "(...) expansion from config values" bullet in the
# prompt is garbled in the source text; its syntax is unknown, so it is skipped.

declare -gA SA_CONF=()

_sa_config_error() {  # Clear partially parsed values on every failure.
  echo "$*" >&2
  SA_CONF=()
  return 1
}

sa_config_load() {  # <file>
  local file=${1-} line n=0 section="" key val
  local -a dups=()
  local -A seen=()
  SA_CONF=()
  [ "$#" -eq 1 ] && [ -n "$file" ] || { _sa_config_error "config: usage: sa_config_load <file>"; return 1; }
  [ -f "$file" ] || { _sa_config_error "config: not found: $file"; return 1; }
  [ -r "$file" ] || { _sa_config_error "config: not readable: $file"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1))
    line=${line#"${line%%[![:space:]]*}"}   # ltrim
    line=${line%"${line##*[![:space:]]}"}   # rtrim
    case $line in ''|'#'*) continue ;; esac
    if [[ $line =~ ^\[([A-Za-z0-9_.-]+)\]$ ]]; then
      section=${BASH_REMATCH[1]}; continue
    fi
    if [[ $line =~ ^([A-Za-z0-9_.-]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key=${BASH_REMATCH[1]}; val=${BASH_REMATCH[2]}
      if [ -z "$section" ]; then
        _sa_config_error "config:$n: key outside any section: $key"; return 1
      fi
      if [[ $val =~ ^\"(.*)\"$ ]]; then val=${BASH_REMATCH[1]}; fi
      if [ -n "${seen[$section.$key]+x}" ]; then dups+=("$n:$section.$key"); fi
      seen[$section.$key]=1
      SA_CONF[$section.$key]=$val       # last wins in storage
      continue
    fi
    _sa_config_error "config:$n: unparseable line"; return 1
  done < "$file"

  if [ "${SA_CONF[meta.config_version]-}" != 1 ]; then
    echo "config: [meta] config_version = 1 required (got '${SA_CONF[meta.config_version]-}')" >&2
    _sa_config_error "config: invalid or missing config_version"; return 1
  fi
  if [ "${#dups[@]}" -gt 0 ]; then
    local d
    if [ "${SA_CONF[meta.allow_override]-}" = 1 ]; then
      for d in "${dups[@]}"; do echo "config: WARNING duplicate key (last wins) at ${d}" >&2; done
    else
      for d in "${dups[@]}"; do echo "config: ERROR duplicate key at ${d}" >&2; done
      _sa_config_error "config: duplicate keys are not allowed"; return 1
    fi
  fi
  return 0
}

sa_config_get() {  # <section.key> [default]
  if [ -n "${SA_CONF[$1]+x}" ]; then printf '%s\n' "${SA_CONF[$1]}"
  elif [ $# -ge 2 ]; then printf '%s\n' "$2"
  else return 1; fi
}


# Schema v1 validator. This is opt-in: loading an INI file remains generic.
_sa_cfg_uint() { local n=${1-}; [[ $n =~ ^[0-9]{1,10}$ ]] && (( 10#$n >= ${2:-1} && 10#$n <= ${3:-2147483647} )); }
_sa_cfg_domain() {
  local d=${1,,} label
  [[ ${#d} -le 253 && $d != .* && $d != *. && $d != *..* ]] || return 1
  [[ $d =~ ^[a-z0-9.-]+$ ]] || return 1
  IFS=. read -r -a _sa_labels <<< "$d"
  for label in "${_sa_labels[@]}"; do
    [[ ${#label} -le 63 && $label =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
  done
}
_sa_cfg_bad() { echo "config schema: $*" >&2; return 1; }

sa_config_validate() {
  local key value section slug site_count=0 required
  local -A site_seen=() seen_domains=() seen_users=() seen_pools=()
  [ "$#" -eq 0 ] || { _sa_cfg_bad "usage: sa_config_validate"; return 64; }
  [ "${SA_CONF[meta.config_version]-}" = 1 ] || { _sa_cfg_bad "config_version 1 is required"; return 1; }

  for key in "${!SA_CONF[@]}"; do
    section=${key%%.*}; value=${SA_CONF[$key]}
    case "$section" in
      meta)
        case "${key#*.}" in
          config_version) [ "$value" = 1 ] || { _sa_cfg_bad "meta.config_version must be 1"; return 1; } ;;
          allow_override) [[ $value == 0 || $value == 1 ]] || { _sa_cfg_bad "meta.allow_override must be 0 or 1"; return 1; } ;;
          *) _sa_cfg_bad "unknown key $key"; return 1 ;;
        esac ;;
      server)
        case "${key#*.}" in
          role) [[ $value == master_lemp || $value == slave_web ]] || { _sa_cfg_bad "server.role must be master_lemp or slave_web"; return 1; } ;;
          tenant_mode) [[ $value == pool || $value == free_for_all ]] || { _sa_cfg_bad "server.tenant_mode must be pool or free_for_all"; return 1; } ;;
          sites_dir) [[ $value == /* && $value != *..* && $value =~ ^/[A-Za-z0-9._/-]+$ ]] || { _sa_cfg_bad "server.sites_dir must be a normalized absolute path"; return 1; } ;;
          *) _sa_cfg_bad "unknown key $key"; return 1 ;;
        esac ;;
      php)
        [[ ${key#*.} == workload ]] || { _sa_cfg_bad "unknown key $key"; return 1; }
        case "$value" in plain|wordpress|laravel|xcart) ;; *) _sa_cfg_bad "php.workload is unsupported"; return 1 ;; esac ;;
      redis)
        case "$key" in
          redis.sessions.enabled|redis.cache.enabled) [[ $value == true || $value == false ]] || { _sa_cfg_bad "$key must be true or false"; return 1; } ;;
          redis.sessions.maxmemory_mib|redis.cache.maxmemory_mib) _sa_cfg_uint "$value" 1 1048576 || { _sa_cfg_bad "$key must be an integer from 1 to 1048576"; return 1; } ;;
          redis.sessions.maxmemory_policy|redis.cache.maxmemory_policy)
            case "$value" in noeviction|allkeys-lru|allkeys-lfu|volatile-lru|volatile-lfu|volatile-random|allkeys-random|volatile-ttl) ;; *) _sa_cfg_bad "$key has an unsupported Redis eviction policy"; return 1 ;; esac ;;
          redis.sessions.port|redis.cache.port) _sa_cfg_uint "$value" 1 65535 || { _sa_cfg_bad "$key must be a TCP port"; return 1; } ;;
          *) _sa_cfg_bad "unknown key $key"; return 1 ;;
        esac ;;
      site)
        slug=${key#site.}; slug=${slug%%.*}
        [[ $slug =~ ^[a-z][a-z0-9_-]{0,31}$ && $key == site.$slug.* ]] || { _sa_cfg_bad "invalid site section/key $key"; return 1; }
        site_seen[$slug]=1
        case "${key#site.$slug.}" in
          domain) _sa_cfg_domain "$value" || { _sa_cfg_bad "$key must be a valid DNS hostname"; return 1; } ;;
          user|pool) [[ $value =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { _sa_cfg_bad "$key has an invalid Unix identity name"; return 1; } ;;
          isolation) [[ $value == pool || $value == free_for_all ]] || { _sa_cfg_bad "$key must be pool or free_for_all"; return 1; } ;;
          memory_max_mib) _sa_cfg_uint "$value" 16 1048576 || { _sa_cfg_bad "$key must be between 16 and 1048576 MiB"; return 1; } ;;
          cpu_quota_pct) _sa_cfg_uint "$value" 1 10000 || { _sa_cfg_bad "$key must be between 1 and 10000 percent"; return 1; } ;;
          egress) [[ $value == loopback_db_only ]] || { _sa_cfg_bad "$key must be loopback_db_only"; return 1; } ;;
          open_basedir_extra)
            if [ -n "$value" ]; then
              [[ $value != *..* && $value != *' '* && $value != *'|'* && $value == /* && $value != *::* && $value != *: ]] || { _sa_cfg_bad "$key must be empty or colon-separated absolute paths"; return 1; }
              local p; IFS=: read -r -a _sa_paths <<< "$value"
              for p in "${_sa_paths[@]}"; do [[ $p == /* && $p != *..* ]] || { _sa_cfg_bad "$key contains an unsafe path"; return 1; }; done
            fi ;;
          php_version) [[ $value =~ ^[0-9]+\.[0-9]+$ ]] || { _sa_cfg_bad "$key must use major.minor format"; return 1; } ;;
          *) _sa_cfg_bad "unknown key $key"; return 1 ;;
        esac ;;
      *) _sa_cfg_bad "unknown section in key $key"; return 1 ;;
    esac
  done

  for slug in "${!site_seen[@]}"; do
    for required in domain user pool isolation; do
      [ -n "${SA_CONF[site.$slug.$required]-}" ] || { _sa_cfg_bad "site.$slug.$required is required"; return 1; }
    done
  done
  local tenant_mode=${SA_CONF[server.tenant_mode]-pool} domain user pool
  for slug in "${!site_seen[@]}"; do
    domain=${SA_CONF[site.$slug.domain],,}
    user=${SA_CONF[site.$slug.user]}
    pool=${SA_CONF[site.$slug.pool]}
    [ -z "${seen_domains[$domain]+x}" ] || { _sa_cfg_bad "duplicate site domain $domain"; return 1; }
    [ -z "${seen_users[$user]+x}" ] || { _sa_cfg_bad "site Unix users must be unique ($user)"; return 1; }
    [ -z "${seen_pools[$pool]+x}" ] || { _sa_cfg_bad "site PHP-FPM pool names must be unique ($pool)"; return 1; }
    seen_domains[$domain]=1; seen_users[$user]=1; seen_pools[$pool]=1
    if [ "$tenant_mode" = pool ] && [ "${SA_CONF[site.$slug.isolation]}" != pool ]; then
      _sa_cfg_bad "site.$slug.isolation must be pool when server.tenant_mode=pool"; return 1
    fi
    if [ "$tenant_mode" = free_for_all ] && [ "${SA_CONF[site.$slug.isolation]}" != free_for_all ]; then
      _sa_cfg_bad "site.$slug.isolation must be free_for_all when server.tenant_mode=free_for_all"; return 1
    fi
  done
  site_count=${#site_seen[@]}
  if [ "$tenant_mode" = free_for_all ] && (( site_count > 1 )); then
    _sa_cfg_bad "free_for_all permits one site only"; return 1
  fi
  return 0
}
