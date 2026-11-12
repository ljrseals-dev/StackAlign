#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/render.sh -- template rendering. Written from master prompt v8 Part III.
# Substitution: {{NAME}}, NAME = [A-Za-z0-9_]+, single pass, no re-expansion,
# via bash parameter expansion / regex only (no sed -i, no eval).
# <map-var-name> is the NAME of an associative array holding the values.

_sa_render_to_var() {  # <template> <map-var-name> <out-var-name>
  local tpl=$1 mapname=$2 outname=$3
  [ -f "$tpl" ] || { echo "sa_render: template not found: $tpl" >&2; return 1; }
  local -n _map=$mapname
  local -n _out=$outname
  local rest out="" name
  rest=$(cat -- "$tpl"; printf x); rest=${rest%x}   # keep trailing newlines
  local re='\{\{([A-Za-z0-9_]+)\}\}'
  while [[ $rest =~ $re ]]; do
    name=${BASH_REMATCH[1]}
    local before=${rest%%"${BASH_REMATCH[0]}"*}
    out+=$before
    if [ -n "${_map[$name]+set}" ]; then
      out+=${_map[$name]}
    elif [ "${SA_RENDER_ALLOW_UNBOUND:-0}" = 1 ]; then
      :
    else
      echo "sa_render: unbound variable: $name" >&2; return 2
    fi
    rest=${rest#*"${BASH_REMATCH[0]}"}   # single pass: substituted text never rescanned
  done
  _out=$out$rest
}

# Read-only diff. Writes nothing.
sa_render_plan() {  # <template> <output> <map-var-name>
  local rendered
  _sa_render_to_var "$1" "$3" rendered || return $?
  if [ -e "$2" ]; then
    diff -u -- "$2" <(printf '%s' "$rendered") || true
  else
    diff -u /dev/null <(printf '%s' "$rendered") || true
  fi
  return 0
}

# Atomic write; byte-identical output is a no-op.
sa_render_apply() {  # <template> <output> <map-var-name>
  local tpl=$1 output=$2 mapname=$3 rendered tmp
  _sa_render_to_var "$tpl" "$mapname" rendered || return $?
  local _sa_cmp
  _sa_cmp=$(mktemp) || return 1
  printf '%s' "$rendered" > "$_sa_cmp" || { rm -f -- "$_sa_cmp"; return 1; }
  if [ -f "$output" ] && cmp -s -- "$output" "$_sa_cmp"; then
    rm -f -- "$_sa_cmp"
    echo "unchanged: $output"; return 0
  fi
  rm -f -- "$_sa_cmp"
  if declare -F sa_history_snapshot >/dev/null; then
    sa_history_snapshot "$output" render >/dev/null || return $?
  fi
  mkdir -p -- "$(dirname -- "$output")"
  tmp=$(mktemp "$(dirname -- "$output")/.sa-render.XXXXXX") || return 1
  printf '%s' "$rendered" > "$tmp" || { rm -f -- "$tmp"; return 1; }
  if [ -e "$output" ]; then chmod --reference="$output" -- "$tmp"; else chmod 0644 -- "$tmp"; fi
  mv -f -- "$tmp" "$output"
  echo "written: $output"
}
