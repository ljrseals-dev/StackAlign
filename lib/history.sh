#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
#
# lib/history.sh -- snapshots. Written from master prompt v8 Part III.
# Config (env, for tests): SA_HISTORY_ROOT (default /etc/stackalign/.history),
# SA_SECRETS_DIR (default /etc/stackalign/secrets).

: "${SA_HISTORY_ROOT:=/etc/stackalign/.history}"
: "${SA_SECRETS_DIR:=/etc/stackalign/secrets}"

_sa_hist_abs() { local p=$1; case $p in /*) printf '%s' "$p" ;; *) printf '%s/%s' "$PWD" "$p" ;; esac; }

# Snapshot IDs are generated as UTC timestamp + validated slug. Never accept
# path separators or traversal components from CLI/library callers.
_sa_hist_id_valid() {
  [[ ${1-} =~ ^[0-9]{8}T[0-9]{6}Z-[A-Za-z0-9_.-]+$ ]]
}

_sa_hist_root_validate() {
  local root=${SA_HISTORY_ROOT:-} resolved mode owner
  [[ $root == /* && $root != *..* && $root != *$'\n'* && $root != *$'\r'* ]] || return 1
  [ -d "$root" ] && [ ! -L "$root" ] || return 1
  resolved=$(/usr/bin/realpath -e -- "$root" 2>/dev/null) || return 1
  [[ $resolved == "$root" ]] || return 1
  read -r mode owner < <(/usr/bin/stat -c '%a %u' -- "$root" 2>/dev/null) || return 1
  [[ $mode == 700 && $owner == "$(/usr/bin/id -u)" ]]
}

_sa_hist_root_prepare() {
  local root=${SA_HISTORY_ROOT:-} normalized
  [[ $root == /* && $root != *..* && $root != *$'\n'* && $root != *$'\r'* ]] || return 1
  normalized=$(/usr/bin/realpath -m -- "$root" 2>/dev/null) || return 1
  [[ $normalized == "$root" ]] || return 1
  ( umask 077; /usr/bin/mkdir -p -- "$root" ) || return 1
  /usr/bin/chmod 0700 -- "$root" || return 1
  _sa_hist_root_validate
}

# sa_history_snapshot <path> [slug] -> prints snapshot id
sa_history_snapshot() {
  local path slug=${2:-snap} ts id dir path_real secret_real
  [ $# -ge 1 ] || { echo "sa_history_snapshot: path required" >&2; return 64; }
  path=$(_sa_hist_abs "$1")
  if [[ $path == *  secret_real=$(/usr/bin/realpath -m -- "$SA_SECRETS_DIR" 2>/dev/null) || return 1
  case "$path_real" in
    "$secret_real"|"$secret_real"/*)
      echo "sa_history_snapshot: refusing secrets path" >&2
      return 3 ;;
  esac
  _sa_hist_root_prepare || { echo "sa_history_snapshot: history root is unsafe or not privately owned" >&2; return 1; }
  ts=$(/usr/bin/date -u +%Y%m%dT%H%M%SZ)
  id="$ts-$slug"
  dir="$SA_HISTORY_ROOT/$id"
  if [ -f "$dir/manifest" ] && /usr/bin/grep -qxF "$(printf '1\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  if [ -f "$dir/manifest" ] && /usr/bin/grep -qxF "$(printf '0\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  [ ! -L "$dir" ] && [ ! -L "$dir/manifest" ] && [ ! -L "$dir/undo.sh" ] || {
    echo "sa_history_snapshot: refusing symlinked snapshot controls" >&2
    return 1
  }
  ( umask 077; /usr/bin/mkdir -p -- "$dir/snapshot" ) || return 1
  if [ -e "$path" ] || [ -L "$path" ]; then
    ( umask 077; /usr/bin/mkdir -p -- "$dir/snapshot$(/usr/bin/dirname -- "$path")" ) || return 1
    /usr/bin/cp -a -- "$path" "$dir/snapshot$path" || return 1
    ( umask 077; printf '1\t%s\n' "$path" >> "$dir/manifest" )
  else
    ( umask 077; printf '0\t%s\n' "$path" >> "$dir/manifest" )
  fi
  _sa_hist_write_undo "$dir"
  printf "stackalign: snapshot created (%s)\n" "$id" >&2
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
        printf 'target=%q\n' "$p"
        printf 'snapshot=%q\n' "$dir/snapshot$p"
        printf 'parent=$(dirname -- "$target")\n'
        printf 'base=$(basename -- "$target")\n'
        printf 'stage="$parent/.$base.stackalign-new.$$"\n'
        printf 'backup="$parent/.$base.stackalign-old.$$"\n'
        printf 'mkdir -p -- "$parent"\n'
        printf 'cp -a -- "$snapshot" "$stage"\n'
        printf 'had_old=0\n'
        printf 'if [ -e "$target" ] || [ -L "$target" ]; then mv -T -- "$target" "$backup"; had_old=1; fi\n'
        printf 'if ! mv -T -- "$stage" "$target"; then\n'
        printf '  if [ "$had_old" -eq 1 ]; then mv -T -- "$backup" "$target"; fi\n'
        printf '  rm -rf -- "$stage"\n'
        printf '  exit 1\n'
        printf 'fi\n'
        printf 'if [ "$had_old" -eq 1 ]; then rm -rf -- "$backup"; fi\n'
      else
        printf 'rm -rf -- %q\n' "$p"
      fi
    done < "$dir/manifest"
  } > "$dir/undo.sh"
  /usr/bin/chmod 0700 -- "$dir/undo.sh"
}

sa_history_path() {
  [ $# -eq 1 ] && _sa_hist_id_valid "$1" || {
    echo "sa_history_path: invalid snapshot id" >&2
    return 64
  }
  printf '%s/%s\n' "$SA_HISTORY_ROOT" "$1"
}

sa_history_list() {
  [ -d "$SA_HISTORY_ROOT" ] || return 0
  _sa_hist_root_validate || { echo "sa_history_list: history root is unsafe" >&2; return 1; }
  local d
  for d in "$SA_HISTORY_ROOT"/*/; do
    [ -f "${d}manifest" ] && /usr/bin/basename -- "$d"
  done
  return 0
}

sa_history_rollback() {
  [ $# -eq 1 ] && _sa_hist_id_valid "$1" || {
    echo "sa_history_rollback: invalid snapshot id" >&2
    return 64
  }
  local id=$1 dir
  _sa_hist_root_validate || { echo "sa_history_rollback: history root is unsafe" >&2; return 1; }
  dir=$(sa_history_path "$id") || return $?
  [ -d "$dir" ] && [ ! -L "$dir" ] &&
    [ -f "$dir/manifest" ] && [ ! -L "$dir/manifest" ] &&
    [ -f "$dir/undo.sh" ] && [ ! -L "$dir/undo.sh" ] || {
      echo "sa_history_rollback: snapshot is missing or unsafe" >&2
      return 1
    }
  printf "stackalign: executing history rollback (%s)\n" "$id" >&2
  if [ -x /usr/bin/logger ]; then /usr/bin/logger -t stackalign "history rollback $id" 2>/dev/null || true; fi
  /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C /usr/bin/bash -p "$dir/undo.sh"
}
\n'* || $path == *  secret_real=$(/usr/bin/realpath -m -- "$SA_SECRETS_DIR" 2>/dev/null) || return 1
  case "$path_real" in
    "$secret_real"|"$secret_real"/*)
      echo "sa_history_snapshot: refusing secrets path" >&2
      return 3 ;;
  esac
  _sa_hist_root_prepare || { echo "sa_history_snapshot: history root is unsafe or not privately owned" >&2; return 1; }
  case $slug in *[!A-Za-z0-9_.-]*) echo "sa_history_snapshot: bad slug" >&2; return 64 ;; esac
  ts=$(/usr/bin/date -u +%Y%m%dT%H%M%SZ)
  id="$ts-$slug"
  dir="$SA_HISTORY_ROOT/$id"
  if [ -f "$dir/manifest" ] && /usr/bin/grep -qxF "$(printf '1\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  if [ -f "$dir/manifest" ] && /usr/bin/grep -qxF "$(printf '0\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  [ ! -L "$dir" ] && [ ! -L "$dir/manifest" ] && [ ! -L "$dir/undo.sh" ] || {
    echo "sa_history_snapshot: refusing symlinked snapshot controls" >&2
    return 1
  }
  ( umask 077; /usr/bin/mkdir -p -- "$dir/snapshot" ) || return 1
  if [ -e "$path" ] || [ -L "$path" ]; then
    ( umask 077; /usr/bin/mkdir -p -- "$dir/snapshot$(/usr/bin/dirname -- "$path")" ) || return 1
    /usr/bin/cp -a -- "$path" "$dir/snapshot$path" || return 1
    ( umask 077; printf '1\t%s\n' "$path" >> "$dir/manifest" )
  else
    ( umask 077; printf '0\t%s\n' "$path" >> "$dir/manifest" )
  fi
  _sa_hist_write_undo "$dir"
  printf "stackalign: snapshot created (%s)\n" "$id" >&2
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
        printf 'target=%q\n' "$p"
        printf 'snapshot=%q\n' "$dir/snapshot$p"
        printf 'parent=$(dirname -- "$target")\n'
        printf 'base=$(basename -- "$target")\n'
        printf 'stage="$parent/.$base.stackalign-new.$$"\n'
        printf 'backup="$parent/.$base.stackalign-old.$$"\n'
        printf 'mkdir -p -- "$parent"\n'
        printf 'cp -a -- "$snapshot" "$stage"\n'
        printf 'had_old=0\n'
        printf 'if [ -e "$target" ] || [ -L "$target" ]; then mv -T -- "$target" "$backup"; had_old=1; fi\n'
        printf 'if ! mv -T -- "$stage" "$target"; then\n'
        printf '  if [ "$had_old" -eq 1 ]; then mv -T -- "$backup" "$target"; fi\n'
        printf '  rm -rf -- "$stage"\n'
        printf '  exit 1\n'
        printf 'fi\n'
        printf 'if [ "$had_old" -eq 1 ]; then rm -rf -- "$backup"; fi\n'
      else
        printf 'rm -rf -- %q\n' "$p"
      fi
    done < "$dir/manifest"
  } > "$dir/undo.sh"
  /usr/bin/chmod 0700 -- "$dir/undo.sh"
}

sa_history_path() {
  [ $# -eq 1 ] && _sa_hist_id_valid "$1" || {
    echo "sa_history_path: invalid snapshot id" >&2
    return 64
  }
  printf '%s/%s\n' "$SA_HISTORY_ROOT" "$1"
}

sa_history_list() {
  [ -d "$SA_HISTORY_ROOT" ] || return 0
  _sa_hist_root_validate || { echo "sa_history_list: history root is unsafe" >&2; return 1; }
  local d
  for d in "$SA_HISTORY_ROOT"/*/; do
    [ -f "${d}manifest" ] && /usr/bin/basename -- "$d"
  done
  return 0
}

sa_history_rollback() {
  [ $# -eq 1 ] && _sa_hist_id_valid "$1" || {
    echo "sa_history_rollback: invalid snapshot id" >&2
    return 64
  }
  local id=$1 dir
  _sa_hist_root_validate || { echo "sa_history_rollback: history root is unsafe" >&2; return 1; }
  dir=$(sa_history_path "$id") || return $?
  [ -d "$dir" ] && [ ! -L "$dir" ] &&
    [ -f "$dir/manifest" ] && [ ! -L "$dir/manifest" ] &&
    [ -f "$dir/undo.sh" ] && [ ! -L "$dir/undo.sh" ] || {
      echo "sa_history_rollback: snapshot is missing or unsafe" >&2
      return 1
    }
  printf "stackalign: executing history rollback (%s)\n" "$id" >&2
  if [ -x /usr/bin/logger ]; then /usr/bin/logger -t stackalign "history rollback $id" 2>/dev/null || true; fi
  /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C /usr/bin/bash -p "$dir/undo.sh"
}
\r'* || $path == *  secret_real=$(/usr/bin/realpath -m -- "$SA_SECRETS_DIR" 2>/dev/null) || return 1
  case "$path_real" in
    "$secret_real"|"$secret_real"/*)
      echo "sa_history_snapshot: refusing secrets path" >&2
      return 3 ;;
  esac
  _sa_hist_root_prepare || { echo "sa_history_snapshot: history root is unsafe or not privately owned" >&2; return 1; }
  case $slug in *[!A-Za-z0-9_.-]*) echo "sa_history_snapshot: bad slug" >&2; return 64 ;; esac
  ts=$(/usr/bin/date -u +%Y%m%dT%H%M%SZ)
  id="$ts-$slug"
  dir="$SA_HISTORY_ROOT/$id"
  if [ -f "$dir/manifest" ] && /usr/bin/grep -qxF "$(printf '1\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  if [ -f "$dir/manifest" ] && /usr/bin/grep -qxF "$(printf '0\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  [ ! -L "$dir" ] && [ ! -L "$dir/manifest" ] && [ ! -L "$dir/undo.sh" ] || {
    echo "sa_history_snapshot: refusing symlinked snapshot controls" >&2
    return 1
  }
  ( umask 077; /usr/bin/mkdir -p -- "$dir/snapshot" ) || return 1
  if [ -e "$path" ] || [ -L "$path" ]; then
    ( umask 077; /usr/bin/mkdir -p -- "$dir/snapshot$(/usr/bin/dirname -- "$path")" ) || return 1
    /usr/bin/cp -a -- "$path" "$dir/snapshot$path" || return 1
    ( umask 077; printf '1\t%s\n' "$path" >> "$dir/manifest" )
  else
    ( umask 077; printf '0\t%s\n' "$path" >> "$dir/manifest" )
  fi
  _sa_hist_write_undo "$dir"
  printf "stackalign: snapshot created (%s)\n" "$id" >&2
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
        printf 'target=%q\n' "$p"
        printf 'snapshot=%q\n' "$dir/snapshot$p"
        printf 'parent=$(dirname -- "$target")\n'
        printf 'base=$(basename -- "$target")\n'
        printf 'stage="$parent/.$base.stackalign-new.$$"\n'
        printf 'backup="$parent/.$base.stackalign-old.$$"\n'
        printf 'mkdir -p -- "$parent"\n'
        printf 'cp -a -- "$snapshot" "$stage"\n'
        printf 'had_old=0\n'
        printf 'if [ -e "$target" ] || [ -L "$target" ]; then mv -T -- "$target" "$backup"; had_old=1; fi\n'
        printf 'if ! mv -T -- "$stage" "$target"; then\n'
        printf '  if [ "$had_old" -eq 1 ]; then mv -T -- "$backup" "$target"; fi\n'
        printf '  rm -rf -- "$stage"\n'
        printf '  exit 1\n'
        printf 'fi\n'
        printf 'if [ "$had_old" -eq 1 ]; then rm -rf -- "$backup"; fi\n'
      else
        printf 'rm -rf -- %q\n' "$p"
      fi
    done < "$dir/manifest"
  } > "$dir/undo.sh"
  /usr/bin/chmod 0700 -- "$dir/undo.sh"
}

sa_history_path() {
  [ $# -eq 1 ] && _sa_hist_id_valid "$1" || {
    echo "sa_history_path: invalid snapshot id" >&2
    return 64
  }
  printf '%s/%s\n' "$SA_HISTORY_ROOT" "$1"
}

sa_history_list() {
  [ -d "$SA_HISTORY_ROOT" ] || return 0
  _sa_hist_root_validate || { echo "sa_history_list: history root is unsafe" >&2; return 1; }
  local d
  for d in "$SA_HISTORY_ROOT"/*/; do
    [ -f "${d}manifest" ] && /usr/bin/basename -- "$d"
  done
  return 0
}

sa_history_rollback() {
  [ $# -eq 1 ] && _sa_hist_id_valid "$1" || {
    echo "sa_history_rollback: invalid snapshot id" >&2
    return 64
  }
  local id=$1 dir
  _sa_hist_root_validate || { echo "sa_history_rollback: history root is unsafe" >&2; return 1; }
  dir=$(sa_history_path "$id") || return $?
  [ -d "$dir" ] && [ ! -L "$dir" ] &&
    [ -f "$dir/manifest" ] && [ ! -L "$dir/manifest" ] &&
    [ -f "$dir/undo.sh" ] && [ ! -L "$dir/undo.sh" ] || {
      echo "sa_history_rollback: snapshot is missing or unsafe" >&2
      return 1
    }
  printf "stackalign: executing history rollback (%s)\n" "$id" >&2
  if [ -x /usr/bin/logger ]; then /usr/bin/logger -t stackalign "history rollback $id" 2>/dev/null || true; fi
  /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C /usr/bin/bash -p "$dir/undo.sh"
}
\t'* ]]; then
    echo "sa_history_snapshot: refusing control characters in path" >&2
    return 64
  fi
  case $slug in
    ""|.|..|*[!A-Za-z0-9_.-]*)
      echo "sa_history_snapshot: bad slug" >&2
      return 64 ;;
  esac
  [ "${#slug}" -le 64 ] || { echo "sa_history_snapshot: slug too long" >&2; return 64; }
  path_real=$(/usr/bin/realpath -m -- "$path" 2>/dev/null) || return 1
  [[ $path_real == "$path" ]] || { echo "sa_history_snapshot: refusing non-canonical or symlinked path" >&2; return 64; }
  secret_real=$(/usr/bin/realpath -m -- "$SA_SECRETS_DIR" 2>/dev/null) || return 1
  case "$path_real" in
    "$secret_real"|"$secret_real"/*)
      echo "sa_history_snapshot: refusing secrets path" >&2
      return 3 ;;
  esac
  _sa_hist_root_prepare || { echo "sa_history_snapshot: history root is unsafe or not privately owned" >&2; return 1; }
  case $slug in *[!A-Za-z0-9_.-]*) echo "sa_history_snapshot: bad slug" >&2; return 64 ;; esac
  ts=$(/usr/bin/date -u +%Y%m%dT%H%M%SZ)
  id="$ts-$slug"
  dir="$SA_HISTORY_ROOT/$id"
  if [ -f "$dir/manifest" ] && /usr/bin/grep -qxF "$(printf '1\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  if [ -f "$dir/manifest" ] && /usr/bin/grep -qxF "$(printf '0\t%s' "$path")" "$dir/manifest" 2>/dev/null; then
    printf '%s\n' "$id"; return 0
  fi
  [ ! -L "$dir" ] && [ ! -L "$dir/manifest" ] && [ ! -L "$dir/undo.sh" ] || {
    echo "sa_history_snapshot: refusing symlinked snapshot controls" >&2
    return 1
  }
  ( umask 077; /usr/bin/mkdir -p -- "$dir/snapshot" ) || return 1
  if [ -e "$path" ] || [ -L "$path" ]; then
    ( umask 077; /usr/bin/mkdir -p -- "$dir/snapshot$(/usr/bin/dirname -- "$path")" ) || return 1
    /usr/bin/cp -a -- "$path" "$dir/snapshot$path" || return 1
    ( umask 077; printf '1\t%s\n' "$path" >> "$dir/manifest" )
  else
    ( umask 077; printf '0\t%s\n' "$path" >> "$dir/manifest" )
  fi
  _sa_hist_write_undo "$dir"
  printf "stackalign: snapshot created (%s)\n" "$id" >&2
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
        printf 'target=%q\n' "$p"
        printf 'snapshot=%q\n' "$dir/snapshot$p"
        printf 'parent=$(dirname -- "$target")\n'
        printf 'base=$(basename -- "$target")\n'
        printf 'stage="$parent/.$base.stackalign-new.$$"\n'
        printf 'backup="$parent/.$base.stackalign-old.$$"\n'
        printf 'mkdir -p -- "$parent"\n'
        printf 'cp -a -- "$snapshot" "$stage"\n'
        printf 'had_old=0\n'
        printf 'if [ -e "$target" ] || [ -L "$target" ]; then mv -T -- "$target" "$backup"; had_old=1; fi\n'
        printf 'if ! mv -T -- "$stage" "$target"; then\n'
        printf '  if [ "$had_old" -eq 1 ]; then mv -T -- "$backup" "$target"; fi\n'
        printf '  rm -rf -- "$stage"\n'
        printf '  exit 1\n'
        printf 'fi\n'
        printf 'if [ "$had_old" -eq 1 ]; then rm -rf -- "$backup"; fi\n'
      else
        printf 'rm -rf -- %q\n' "$p"
      fi
    done < "$dir/manifest"
  } > "$dir/undo.sh"
  /usr/bin/chmod 0700 -- "$dir/undo.sh"
}

sa_history_path() {
  [ $# -eq 1 ] && _sa_hist_id_valid "$1" || {
    echo "sa_history_path: invalid snapshot id" >&2
    return 64
  }
  printf '%s/%s\n' "$SA_HISTORY_ROOT" "$1"
}

sa_history_list() {
  [ -d "$SA_HISTORY_ROOT" ] || return 0
  _sa_hist_root_validate || { echo "sa_history_list: history root is unsafe" >&2; return 1; }
  local d
  for d in "$SA_HISTORY_ROOT"/*/; do
    [ -f "${d}manifest" ] && /usr/bin/basename -- "$d"
  done
  return 0
}

sa_history_rollback() {
  [ $# -eq 1 ] && _sa_hist_id_valid "$1" || {
    echo "sa_history_rollback: invalid snapshot id" >&2
    return 64
  }
  local id=$1 dir
  _sa_hist_root_validate || { echo "sa_history_rollback: history root is unsafe" >&2; return 1; }
  dir=$(sa_history_path "$id") || return $?
  [ -d "$dir" ] && [ ! -L "$dir" ] &&
    [ -f "$dir/manifest" ] && [ ! -L "$dir/manifest" ] &&
    [ -f "$dir/undo.sh" ] && [ ! -L "$dir/undo.sh" ] || {
      echo "sa_history_rollback: snapshot is missing or unsafe" >&2
      return 1
    }
  printf "stackalign: executing history rollback (%s)\n" "$id" >&2
  if [ -x /usr/bin/logger ]; then /usr/bin/logger -t stackalign "history rollback $id" 2>/dev/null || true; fi
  /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C /usr/bin/bash -p "$dir/undo.sh"
}
