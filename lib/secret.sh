#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/secret.sh -- password and secret policy. Written from master prompt v8 Part III.
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
  sha=$(printf '%s' "$1" | sha1sum | awk '{print toupper($1)}')
  prefix=${sha:0:5}; suffix=${sha:5}
  body=$(curl -fsS --proto '=https' --tlsv1.2 -- "https://api.pwnedpasswords.com/range/$prefix") || return 2
  if tr -d '\r' <<<"$body" | grep -qiE "^${suffix}:"; then return 0; fi
  return 1
}

_sa_secret_argon2() {  # <password> -> encoded hash on stdout; password via stdin only
  command -v argon2 >/dev/null 2>&1 || { echo "secret: argon2 CLI not installed; refusing weaker fallback" >&2; return 5; }
  local salt; salt=$(openssl rand -hex 8) || return 5
  printf '%s' "$1" | argon2 "$salt" -id -t 2 -m 14 -p 1 -e   # m=14 -> 2^14 KiB = 16 MiB
}

_sa_secret_passphrase() {  # -> passphrase on stdout
  local wl=${SA_WORDLIST:-} n=$SA_PASSPHRASE_WORDS lines
  [ -n "$wl" ] && [ -f "$wl" ] || { echo "secret: SA_WORDLIST not set or not a file (no wordlist is shipped)" >&2; return 5; }
  [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 6 ] || { echo "secret: passphrase needs >= 6 words" >&2; return 64; }
  lines=$(grep -c . "$wl")
  [ "$lines" -ge "$SA_WORDLIST_MIN" ] || { echo "secret: wordlist has $lines words, need >= $SA_WORDLIST_MIN" >&2; return 5; }
  grep . "$wl" | shuf --random-source=/dev/urandom -r -n "$n" | paste -sd- -
}

_sa_secret_legacy() { LC_ALL=C tr -dc 'A-Za-z0-9_-' </dev/urandom | head -c "$SA_LEGACY_LEN"; }

sa_secret_gen() {  # <name> [mode]
  local name=${1:-} mode=${2:-machine} file val hash tries
  _sa_secret_name_ok "$name" || { echo "secret: invalid name (want [a-z0-9_-], <=64)" >&2; return 64; }
  case $mode in machine|human-passphrase|human-legacy) ;; *) echo "secret: unknown mode: $mode" >&2; return 64 ;; esac
  file="$SA_SECRETS_DIR/$name.hash"
  if [ -e "$file" ]; then echo "secret: $name already exists; refusing to overwrite" >&2; return 3; fi
  if [ "${SA_MODE:-apply}" = plan ]; then
    echo "plan: generate $mode secret '$name', store hash at $file (value shown once on --apply)"; return 0
  fi

  case $mode in
    machine)
      command -v openssl >/dev/null 2>&1 || { echo "secret: openssl required" >&2; return 5; }
      val=$(openssl rand -base64 32) || return 5
      hash="sha256:$(printf '%s' "$val" | sha256sum | awk '{print $1}')" ;;
    human-passphrase)
      for tries in 1 2 3 4 5; do
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

  ( umask 077
    mkdir -p -- "$SA_SECRETS_DIR" && chmod 0700 "$SA_SECRETS_DIR" || exit 1
    set -o noclobber
    printf '%s\n' "$hash" > "$file" ) || { echo "secret: could not store hash (exists or unwritable)" >&2; return 3; }

  echo "secret: $name stored as hash at $file; value below is shown ONCE" >&2
  printf '%s\n' "$val"
}

sa_secret_list() {
  [ -d "$SA_SECRETS_DIR" ] || return 0
  local f
  for f in "$SA_SECRETS_DIR"/*.hash; do
    [ -e "$f" ] && basename "${f%.hash}"
  done
  return 0
}
