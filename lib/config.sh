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

sa_config_load() {  # <file>
  local file=$1 line n=0 section="" key val rc=0
  local -a dups=()
  [ -f "$file" ] || { echo "config: not found: $file" >&2; return 1; }
  SA_CONF=()
  declare -A seen=()
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
        echo "config:$n: key outside any section: $key" >&2; return 1
      fi
      if [[ $val =~ ^\"(.*)\"$ ]]; then val=${BASH_REMATCH[1]}; fi
      if [ -n "${seen[$section.$key]+x}" ]; then dups+=("$n:$section.$key"); fi
      seen[$section.$key]=1
      SA_CONF[$section.$key]=$val       # last wins in storage
      continue
    fi
    echo "config:$n: unparseable line" >&2; return 1
  done < "$file"

  if [ "${SA_CONF[meta.config_version]-}" != 1 ]; then
    echo "config: [meta] config_version = 1 required (got '${SA_CONF[meta.config_version]-}')" >&2
    SA_CONF=(); return 1
  fi
  if [ "${#dups[@]}" -gt 0 ]; then
    local d
    if [ "${SA_CONF[meta.allow_override]-}" = 1 ]; then
      for d in "${dups[@]}"; do echo "config: WARNING duplicate key (last wins) at ${d}" >&2; done
    else
      for d in "${dups[@]}"; do echo "config: ERROR duplicate key at ${d}" >&2; done
      SA_CONF=(); return 1
    fi
  fi
  return $rc
}

sa_config_get() {  # <section.key> [default]
  if [ -n "${SA_CONF[$1]+x}" ]; then printf '%s\n' "${SA_CONF[$1]}"
  elif [ $# -ge 2 ]; then printf '%s\n' "$2"
  else return 1; fi
}
