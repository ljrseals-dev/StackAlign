#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/history.sh -- snapshots. Written from master prompt v8 Part III.
# Config (env, for tests): SA_HISTORY_ROOT (default /etc/stackalign/.history),
# SA_SECRETS_DIR (default /etc/stackalign/secrets).

: "${SA_HISTORY_ROOT:=/etc/stackalign/.history}"
: "${SA_SECRETS_DIR:=/etc/stackalign/secrets}"

_sa_hist_abs() { local p=$1; case $p in /*) printf '%s' "$p" ;; *) printf '%s/%s' "$PWD" "$p" ;; esac; }

# sa_history_snapshot <path> [slug] -> prints snapshot id
sa_history_snapshot() {
  local path slug=${2:-snap} ts id dir
  [ $# -ge 1 ] || { echo "sa_history_snapshot: path required" >&2; return 64; }
  path=$(_sa_hist_abs "$1")
  case $path in
    "$SA_SECRETS_DIR"|"$SA_SECRETS_DIR"/*)
      if [ "${SA_HISTORY_ALLOW_SECRETS:-0}" != 1 ]; then
        echo "sa_history_snapshot: refusing secrets path $path" >&2; return 3
      fi
      echo "WARNING: snapshotting secrets path $path (SA_HISTORY_ALLOW_SECRETS=1)" >&2 ;;
  esac
  case $slug in *[!A-Za-z0-9_.-]*) echo "sa_history_snapshot: bad slug" >&2; return 64 ;; esac
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  id="$ts-$slug"
  dir="$SA_HISTORY_ROOT/$id"
  # Idempotent within the same second for the same path+slug.
  if [ -f "$dir/manifest" ] && grep -qxF "$(printf '1\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  if [ -f "$dir/manifest" ] && grep -qxF "$(printf '0\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  mkdir -p "$dir/snapshot" || return 1
  if [ -e "$path" ] || [ -L "$path" ]; then
    mkdir -p "$dir/snapshot$(dirname "$path")"
    cp -a "$path" "$dir/snapshot$path" || return 1
    printf '1\t%s\n' "$path" >> "$dir/manifest"
  else
    printf '0\t%s\n' "$path" >> "$dir/manifest"
  fi
  _sa_hist_write_undo "$dir"
  printf '%s\n' "$id"
}

_sa_hist_write_undo() {
  local dir=$1
  {
    echo '#!/usr/bin/env bash'
    echo "# generated undo for $dir"
    echo 'set -eu'
    local existed p
    while IFS=$'\t' read -r existed p; do
      if [ "$existed" = 1 ]; then
        printf 'rm -rf %q\n' "$p"
        printf 'mkdir -p %q\n' "$(dirname "$p")"
        printf 'cp -a %q %q\n' "$dir/snapshot$p" "$p"
      else
        printf 'rm -rf %q\n' "$p"
      fi
    done < "$dir/manifest"
  } > "$dir/undo.sh"
  chmod 0700 "$dir/undo.sh"
}

sa_history_path() { printf '%s/%s\n' "$SA_HISTORY_ROOT" "$1"; }

sa_history_list() {
  [ -d "$SA_HISTORY_ROOT" ] || return 0
  local d
  for d in "$SA_HISTORY_ROOT"/*/; do
    [ -f "${d}manifest" ] && basename "$d"
  done
  return 0
}

sa_history_rollback() {
  local id=$1 dir
  dir=$(sa_history_path "$id")
  [ -f "$dir/manifest" ] || { echo "sa_history_rollback: unknown id $id" >&2; return 1; }
  bash "$dir/undo.sh"
}
