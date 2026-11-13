#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/fetch.sh -- safe downloads for StackAlign-managed standalone artifacts.
# DNF repository/package downloads remain DNF's responsibility.

_sa_fetch_valid_https_url() {
  [[ $# -eq 1 && $1 =~ ^https://[A-Za-z0-9._~:/?#@!$\&\'\(\)\*+,\;=%-]+$ ]]
}

# sa_fetch_url <url> <output_file> [fallback_url ...]
# Downloads to a private same-directory temporary file and publishes by rename.
# A failed source can never leave a partial output at output_file.
sa_fetch_url() {
  [ $# -ge 2 ] || {
    echo "usage: sa_fetch_url <https-url> <output_file> [fallback_url ...]" >&2
    return 64
  }

  local primary=$1 out=$2 out_dir out_base tmp url rc=0
  shift 2

  _sa_fetch_valid_https_url "$primary" || {
    echo "fetch: refusing non-HTTPS or malformed primary URL" >&2
    return 64
  }
  local -a urls=("$primary")
  for url in "$@"; do
    _sa_fetch_valid_https_url "$url" || {
      echo "fetch: refusing non-HTTPS or malformed fallback URL" >&2
      return 64
    }
    urls+=("$url")
  done

  out_dir=$(dirname -- "$out") || return 1
  out_base=$(basename -- "$out") || return 1
  [ -d "$out_dir" ] || {
    echo "fetch: output directory does not exist: $out_dir" >&2
    return 1
  }
  [ -n "$out_base" ] && [ "$out_base" != "." ] && [ "$out_base" != "/" ] || {
    echo "fetch: invalid output path" >&2
    return 64
  }
  if [ -L "$out" ] || { [ -e "$out" ] && [ ! -f "$out" ]; }; then
    echo "fetch: output exists and is not a regular non-symlink file" >&2
    return 1
  fi

  tmp=$(mktemp "$out_dir/.${out_base}.sa-fetch.XXXXXX") || {
    echo "fetch: cannot create temporary output beside $out" >&2
    return 1
  }
  chmod 0600 "$tmp" || { rm -f -- "$tmp"; return 1; }

  for url in "${urls[@]}"; do
    : > "$tmp" || { rm -f -- "$tmp"; return 1; }
    if curl --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 60 \
        --output "$tmp" -- "$url"; then
      if [ ! -f "$tmp" ] || [ -L "$tmp" ]; then
        echo "fetch: downloader did not produce a regular file" >&2
        rm -f -- "$tmp"
        return 1
      fi
      mv -fT -- "$tmp" "$out" || {
        rm -f -- "$tmp"
        echo "fetch: cannot publish downloaded file: $out" >&2
        return 1
      }
      return 0
    else
      rc=$?
      echo "fetch: source failed (exit $rc): $url" >&2
    fi
  done

  rm -f -- "$tmp"
  echo "fetch: all sources failed; output not published: $out" >&2
  return 1
}

# sa_fetch_verify <file> <expected_sha256>
# SHA-256 verifies bytes, not publisher identity; callers must separately verify
# signatures/fingerprints where the artifact's trust policy requires them.
sa_fetch_verify() {
  [ $# -eq 2 ] || {
    echo "usage: sa_fetch_verify <file> <expected_sha256>" >&2
    return 64
  }
  local file=$1 expected=$2 actual
  [[ $expected =~ ^[A-Fa-f0-9]{64}$ ]] || {
    echo "fetch: expected SHA-256 must be exactly 64 hexadecimal characters" >&2
    return 64
  }
  [ -f "$file" ] && [ ! -L "$file" ] || {
    echo "fetch: verification target must be a regular non-symlink file" >&2
    return 1
  }
  actual=$(sha256sum -- "$file") || {
    echo "fetch: sha256sum failed: $file" >&2
    return 1
  }
  actual=${actual:0:64}
  if [ "${actual,,}" != "${expected,,}" ]; then
    echo "fetch: SHA-256 mismatch (expected $expected, got $actual)" >&2
    return 1
  fi
  return 0
}
