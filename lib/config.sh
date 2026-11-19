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

_sa_config_key_allowed() {
  case "$1.$2" in
    meta.config_version|meta.allow_override|security.password_mode|security.passphrase_wordlist) return 0 ;;
    *) return 1 ;;
  esac
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
      _sa_config_key_allowed "$section" "$key" || {
        _sa_config_error "config:$n: unknown key: $section.$key"; return 1
      }
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
  if [ -n "${SA_CONF[meta.allow_override]-}" ] && [[ ! ${SA_CONF[meta.allow_override]} =~ ^(0|1)$ ]]; then
    _sa_config_error "config: meta.allow_override must be 0 or 1"; return 1
  fi
  if [ -n "${SA_CONF[security.password_mode]-}" ]; then
    case ${SA_CONF[security.password_mode]} in
      machine|human-passphrase|human-legacy) ;;
      *) _sa_config_error "config: invalid security.password_mode"; return 1 ;;
    esac
  fi
  if [ -n "${SA_CONF[security.passphrase_wordlist]-}" ]; then
    local wl=${SA_CONF[security.passphrase_wordlist]} resolved
    [[ $wl == /* && $wl != *..* && $wl != *$'\n'* && $wl != *$'\r'* ]] || {
      _sa_config_error "config: security.passphrase_wordlist must be an absolute canonical path"; return 1
    }
    [ -f "$wl" ] && [ ! -L "$wl" ] || {
      _sa_config_error "config: security.passphrase_wordlist must be a regular non-symlink file"; return 1
    }
    resolved=$(/usr/bin/realpath -e -- "$wl" 2>/dev/null) || {
      _sa_config_error "config: cannot resolve security.passphrase_wordlist"; return 1
    }
    [[ $resolved == "$wl" ]] || {
      _sa_config_error "config: security.passphrase_wordlist is not canonical"; return 1
    }
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
