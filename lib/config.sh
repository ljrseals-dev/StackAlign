#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
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
    local wl resolved
    wl=${SA_CONF[security.passphrase_wordlist]}
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


# sa_config_write_atomic <absolute-path>
# Read configuration bytes from stdin and atomically replace a regular file.
# This primitive is schema-agnostic: callers must validate content before
# invoking it. The parent directory must already exist and be trusted.
#
# Cooperating writers are serialized with an atomic mkdir lock. A stale lock
# after SIGKILL is deliberately not auto-broken; an operator must inspect and
# remove it. This avoids guessing whether another writer is still active.
#
# Existing file mode and ownership are preserved. New files are owner-only
# (0600). Final-component symlinks and non-regular targets are refused.
# The temp file is created beside the target so rename stays on one filesystem.
# Atomic visibility is provided; power-loss durability/fsync is not promised.
sa_config_write_atomic() (
  local requested=${1-} parent base target lock tmp metadata uid gid mode
  local original_id="" current_id=""

  if [ "$#" -ne 1 ] || [[ ! $requested = /* ]]; then
    echo "config: usage: sa_config_write_atomic <absolute-path>" >&2
    exit 64
  fi

  parent=$(dirname -- "$requested")
  base=$(basename -- "$requested")
  case $base in ''|.|..) echo "config: invalid target basename" >&2; exit 64 ;; esac
  if ! parent=$(cd -P -- "$parent" 2>/dev/null && pwd -P); then
    echo "config: parent directory does not exist or is inaccessible" >&2
    exit 1
  fi
  target="$parent/$base"

  if [ -L "$target" ]; then
    echo "config: refusing symlink target: $target" >&2
    exit 1
  fi
  if [ -e "$target" ] && [ ! -f "$target" ]; then
    echo "config: refusing non-regular target: $target" >&2
    exit 1
  fi

  lock="$parent/.$base.stackalign.lock"
  if ! (umask 077; mkdir -- "$lock") 2>/dev/null; then
    echo "config: writer lock exists; refusing concurrent or stale writer: $lock" >&2
    exit 75
  fi

  tmp=""
  _sa_config_write_cleanup() {
    [ -z "$tmp" ] || rm -f -- "$tmp"
    rmdir -- "$lock" 2>/dev/null || :
  }
  trap _sa_config_write_cleanup EXIT
  trap 'exit 1' HUP INT TERM

  if [ -e "$target" ]; then
    metadata=$(stat -c '%u %g %a %d:%i' -- "$target") || exit 1
    read -r uid gid mode original_id <<< "$metadata"
  fi

  tmp=$(umask 077; mktemp -- "$parent/.$base.stackalign.XXXXXX") || {
    echo "config: cannot create staged file in $parent" >&2
    exit 1
  }
  if ! cat > "$tmp"; then
    echo "config: failed to write staged content" >&2
    exit 1
  fi

  if [ -n "$original_id" ]; then
    if ! chown "$uid:$gid" -- "$tmp"; then
      echo "config: cannot preserve target ownership" >&2
      exit 1
    fi
    if ! chmod "$mode" -- "$tmp"; then
      echo "config: cannot preserve target mode" >&2
      exit 1
    fi
    if [ -L "$target" ] || [ ! -f "$target" ]; then
      echo "config: target type changed while staging; refusing replacement" >&2
      exit 1
    fi
    current_id=$(stat -c '%d:%i' -- "$target") || exit 1
    if [ "$current_id" != "$original_id" ]; then
      echo "config: target changed while staging; refusing replacement" >&2
      exit 1
    fi
  else
    if [ -e "$target" ] || [ -L "$target" ]; then
      echo "config: target appeared while staging; refusing replacement" >&2
      exit 1
    fi
    chmod 0600 -- "$tmp" || exit 1
  fi

  if ! mv -fT -- "$tmp" "$target"; then
    echo "config: atomic replacement failed" >&2
    exit 1
  fi
  tmp=""
  exit 0
)
