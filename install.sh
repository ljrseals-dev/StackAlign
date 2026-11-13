#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# install.sh -- bootstrapper. Written from master prompt v8 Part III.
# Downloads ONE pinned release tarball, verifies its SHA-256 against the value
# hardcoded below, extracts to a private temp dir, runs bin/stackalign.
# No other network calls. No telemetry. Not meant to be piped from curl.
#
# M1 SKELETON STATE: EXPECTED_SHA256 is PLACEHOLDER, so this script refuses to
# run. The release process replaces VERSION and EXPECTED_SHA256 at each release.
#
# The pins below are deliberately NOT overridable from the environment.
set -euo pipefail

readonly VERSION="0.0.0-dev"
readonly EXPECTED_SHA256="PLACEHOLDER"
readonly BASE_URL="https://github.com/ljrseals-dev/stackalign/releases/download"

die() { echo "install.sh: $*" >&2; exit "${2:-1}"; }

if [ "$EXPECTED_SHA256" = "PLACEHOLDER" ]; then
  die "refusing to run: EXPECTED_SHA256 is PLACEHOLDER (unreleased skeleton)" 3
fi
[[ $EXPECTED_SHA256 =~ ^[0-9a-f]{64}$ ]] || die "refusing to run: EXPECTED_SHA256 is not 64 lowercase hex" 3

umask 077
TMP=$(mktemp -d) || die "cannot create temp dir"
trap 'rm -rf "$TMP"' EXIT

PKG="$TMP/stackalign-$VERSION.tar.gz"
URL="$BASE_URL/v$VERSION/stackalign-$VERSION.tar.gz"

curl -fsSL --proto '=https' --tlsv1.2 -o "$PKG" "$URL" || die "download failed: $URL" 2

actual=$(sha256sum "$PKG" | awk '{print $1}')
if [ "$actual" != "$EXPECTED_SHA256" ]; then
  die "SHA-256 mismatch: expected $EXPECTED_SHA256, got $actual; nothing extracted" 4
fi

# Refuse unsafe member paths and all symbolic/hard links before extraction.
# Link entries are refused outright to prevent link-order and target traversal.
if tar --quoting-style=escape -tzf "$PKG" | awk '/^\// || /(^|\/)\.\.(\/|$)/ {bad=1} END{exit !bad}'; then
  die "refusing archive with absolute or '..' paths; nothing extracted" 5
fi
if tar --quoting-style=escape -tvzf "$PKG" | awk 'substr($0,1,1) == "l" || substr($0,1,1) == "h" { found=1 } END { exit !found }'; then
  die "refusing archive containing symbolic or hard links; nothing extracted" 5
fi

mkdir "$TMP/x"
tar -xzf "$PKG" -C "$TMP/x" --no-same-owner --no-same-permissions
BIN="$TMP/x/stackalign-$VERSION/bin/stackalign"
[ -f "$BIN" ] && [ -x "$BIN" ] || die "release has no executable bin/stackalign" 5

# Global flags must precede the command in bin/stackalign, so --yes is moved
# ahead of 'install'. Everything else is passed through unchanged.
pre=(); rest=()
for a in "$@"; do
  if [ "$a" = "--yes" ]; then pre+=(--yes); else rest+=("$a"); fi
done
# Not exec: the EXIT trap must still clean the temp dir.
set +e
"$BIN" ${pre[@]+"${pre[@]}"} install --apply ${rest[@]+"${rest[@]}"}
rc=$?
set -e
exit "$rc"
