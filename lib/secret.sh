#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/secret.sh -- password and secret policy. Written from master prompt v8 Part III.
. "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/exec.sh"

# Two primitives, never confused:
#   machine-generated (256-bit random) -> SHA-256 for storage
#   human-chosen (passphrase / legacy) -> Argon2id (>=15 MiB, 2 iters, 1 lane)
# The VALUE is printed to stdout exactly once, after the hash is safely stored.
# It is never written to disk or logs. No composition rules are enforced.
#
# ASSUMPTIONS (spec silent; unmeasured design choices):
#   * only the HASH is stored (per spec), as <name>.hash. NOTE the tension: a
#     machine secret stored only as SHA-256 can be VERIFIED but not re-supplied
#     to a service later. Whether service credentials need a recoverable copy
#     is an open design question, not decided here.
#   * no wordlist is shipped. Passphrase mode needs SA_WORDLIST (one word per
#     line, >= 7776 lines); refuses otherwise. Words joined with '-'.
#   * HIBP unreachable => refuse (rc 6, fail closed), no silent skip.
#   * existing name => refuse (rc 3); never regenerate/overwrite.
#   * Argon2id needs the `argon2` CLI; if absent, refuse (no weaker fallback).
# Return codes: 64 usage/validation, 3 exists, 4 breached/too weak, 5 missing
# tool or wordlist, 6 HIBP unreachable.

: "${SA_SECRETS_DIR:=/etc/stackalign/secrets}"
: "${SA_PASSPHRASE_WORDS:=6}"
: "${SA_LEGACY_LEN:=24}"
SA_WORDLIST_MIN=7776

_sa_secret_name_ok() { [[ $1 =~ ^[a-z0-9][a-z0-9_-]{0,63}$ ]]; }

# 0 = breached, 1 = not breached, 2 = lookup failed. Sends only a 5-hex prefix.
_sa_secret_breached() {
  local sha prefix suffix body
  sha=$(printf '%s' "$1" | /usr/bin/sha1sum | /usr/bin/awk '{print toupper($1)}')
  prefix=${sha:0:5}; suffix=${sha:5}
  body=$(sa_exec curl -- --fail --silent --show-error --connect-timeout 5 --max-time 20 --proto '=https' --tlsv1.2 -- "https://api.pwnedpasswords.com/range/$prefix") || return 2
  if /usr/bin/tr -d '\r' <<<"$body" | /usr/bin/grep -qiE "^${suffix}:"; then return 0; fi
  return 1
}

_sa_secret_argon2_available() { [ -x /usr/bin/argon2 ]; }

_sa_secret_argon2() {  # <password> -> encoded hash on stdout; password via stdin only
  _sa_secret_argon2_available || { echo "secret: argon2 CLI not installed; refusing weaker fallback" >&2; return 5; }
  local salt; salt=$(sa_exec openssl -- rand -hex 8) || return 5
  printf '%s' "$1" | sa_exec argon2 -- "$salt" -id -t 2 -m 14 -p 1 -e   # m=14 -> 2^14 KiB = 16 MiB
}

_sa_secret_wordlist_ok() {
  local wl=${SA_WORDLIST:-} resolved mode owner
  [[ $wl == /* && $wl != *..* && $wl != *$'\n'* && $wl != *$'\r'* ]] || return 1
  [ -f "$wl" ] && [ ! -L "$wl" ] || return 1
  resolved=$(/usr/bin/realpath -e -- "$wl" 2>/dev/null) || return 1
  [[ $resolved == "$wl" ]] || return 1
  read -r mode owner < <(/usr/bin/stat -c '%a %u' -- "$wl" 2>/dev/null) || return 1
  [[ $mode =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$mode & 004) != 0 && (8#$mode & 022) == 0 )) || return 1
  [[ $owner == 0 || $owner == "$(/usr/bin/id -u)" ]]
}
_sa_secret_passphrase() {  # -> passphrase on stdout
  local wl=${SA_WORDLIST:-} n=$SA_PASSPHRASE_WORDS lines
  _sa_secret_wordlist_ok || { echo "secret: SA_WORDLIST must be a canonical, non-symlink, world-readable wordlist (no wordlist is shipped)" >&2; return 5; }
  [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 6 ] || { echo "secret: passphrase needs >= 6 words" >&2; return 64; }
  lines=$(/usr/bin/grep -c . "$wl")
  [ "$lines" -ge "$SA_WORDLIST_MIN" ] || { echo "secret: wordlist has $lines words, need >= $SA_WORDLIST_MIN" >&2; return 5; }
  /usr/bin/grep . "$wl" | /usr/bin/shuf --random-source=/dev/urandom -r -n "$n" | /usr/bin/paste -sd- -
}

_sa_secret_legacy() { LC_ALL=C /usr/bin/tr -dc 'A-Za-z0-9_-' </dev/urandom | /usr/bin/head -c "$SA_LEGACY_LEN"; }

_sa_secret_gen_impl() {  # <name> [mode]
  local name=${1:-} mode=${2:-machine} file val hash
  _sa_secret_name_ok "$name" || { echo "secret: invalid name (want [a-z0-9_-], <=64)" >&2; return 64; }
  case $mode in machine|human-passphrase|human-legacy) ;; *) echo "secret: unknown mode: $mode" >&2; return 64 ;; esac
  file="$SA_SECRETS_DIR/$name.hash"
  if [ -e "$file" ]; then echo "secret: $name already exists; refusing to overwrite" >&2; return 3; fi
  if [ "${SA_MODE:-apply}" = plan ]; then
    echo "plan: generate $mode secret '$name', store hash at $file (value shown once on --apply)"; return 0
  fi

  case $mode in
    machine)
      [ -x /usr/bin/openssl ] || { echo "secret: openssl required" >&2; return 5; }
      val=$(sa_exec openssl -- rand -base64 32) || return 5
      hash="sha256:$(printf '%s' "$val" | /usr/bin/sha256sum | /usr/bin/awk '{print $1}')" ;;
    human-passphrase)
      for _ in 1 2 3 4 5; do
        val=$(_sa_secret_passphrase) || return $?
        _sa_secret_breached "$val"; case $? in
          0) val=""; continue ;;                       # breached: draw again
          2) echo "secret: HIBP lookup failed; refusing (fail closed)" >&2; return 6 ;;
        esac
        break
      done
      [ -n "$val" ] || { echo "secret: every candidate was in a breach corpus" >&2; return 4; }
      [ ${#val} -ge 15 ] || { echo "secret: passphrase shorter than 15 chars" >&2; return 4; }
      hash=$(_sa_secret_argon2 "$val") || return $? ;;
    human-legacy)
      val=$(_sa_secret_legacy)
      [ ${#val} -ge 20 ] || { echo "secret: legacy value shorter than 20 chars" >&2; return 4; }
      hash=$(_sa_secret_argon2 "$val") || return $? ;;
  esac
  [ -n "$hash" ] || { echo "secret: empty hash; nothing stored" >&2; return 1; }

  _sa_secret_dir_prepare || { echo "secret: secrets directory is unsafe or not privately owned" >&2; return 1; }
  local tmp
  tmp=$(umask 077; /usr/bin/mktemp "$SA_SECRETS_DIR/.${name}.XXXXXX") || {
    echo "secret: cannot create private temporary file" >&2
    return 1
  }
  if ! ( umask 077; printf '%s\n' "$hash" > "$tmp" && /usr/bin/chmod 0600 -- "$tmp" ); then
    /usr/bin/rm -f -- "$tmp"
    echo "secret: cannot write private hash file" >&2
    return 1
  fi
  if ! /usr/bin/ln -T -- "$tmp" "$file"; then
    /usr/bin/rm -f -- "$tmp"
    echo "secret: cannot publish hash (name already exists or directory unsafe)" >&2
    return 3
  fi
  /usr/bin/rm -f -- "$tmp" || return 1

  echo "secret: $name stored as hash at $file; value below is shown ONCE" >&2
  printf '%s\n' "$val"
}

_sa_secret_dir_prepare() {
  local dir=${SA_SECRETS_DIR:-} normalized resolved mode owner
  [[ $dir == /* && $dir != *..* && $dir != *$'\n'* && $dir != *$'\r'* ]] || return 1
  normalized=$(/usr/bin/realpath -m -- "$dir" 2>/dev/null) || return 1
  [[ $normalized == "$dir" ]] || return 1
  ( umask 077; /usr/bin/mkdir -p -- "$dir" ) || return 1
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  resolved=$(/usr/bin/realpath -e -- "$dir" 2>/dev/null) || return 1
  [[ $resolved == "$dir" ]] || return 1
  /usr/bin/chmod 0700 -- "$dir" || return 1
  read -r mode owner < <(/usr/bin/stat -c '%a %u' -- "$dir" 2>/dev/null) || return 1
  [[ $mode == 700 && $owner == "$(/usr/bin/id -u)" ]]
}

sa_secret_gen() {
  # A command substitution runs in a subshell; disabling xtrace here cannot
  # protect the caller's assignment trace. Refuse before generating anything.
  case $- in
    *x*) echo "secret: generation refused while xtrace is enabled; disable xtrace first" >&2; return 64 ;;
  esac
  _sa_secret_gen_impl "$@"
}

sa_secret_list() {
  [ -d "$SA_SECRETS_DIR" ] || return 0
  local f
  for f in "$SA_SECRETS_DIR"/*.hash; do
    [ -e "$f" ] && basename "${f%.hash}"
  done
  return 0
}
