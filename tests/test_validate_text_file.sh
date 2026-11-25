#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# tests/test_validate_text_file.sh -- bounded, read-only file preflight tests.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(/usr/bin/mktemp -d)
trap '/usr/bin/rm -rf -- "$TMP"' EXIT
mkdir -m 700 "$TMP/root"
APP_ROOT=$(cd "$TMP/root" && pwd -P)

source "$ROOT/lib/exec.sh"
source "$ROOT/lib/validate.sh"

valid="$APP_ROOT/wp-config.php"
printf '%s\n' "<?php" "define('DB_NAME', 'wordpress');" > "$valid"
chmod 600 "$valid"

sa_validate_text_file_under_root "$APP_ROOT" "$valid"
[ "$SA_VALIDATE_FILE_REASON" = ok ]
sa_validate_close_text_file

empty="$APP_ROOT/empty.php"
: > "$empty"
sa_validate_text_file_under_root "$APP_ROOT" "$empty"
[ "$SA_VALIDATE_FILE_REASON" = ok ]
sa_validate_close_text_file

missing="$APP_ROOT/missing.php"
if sa_validate_text_file_under_root "$APP_ROOT" "$missing"; then
    echo "FAIL: missing file accepted" >&2; exit 1
else
    [ "$?" -eq 66 ]
    [ "$SA_VALIDATE_FILE_REASON" = missing ]
fi

binary="$APP_ROOT/binary.php"
printf 'prefix\000suffix\n' > "$binary"
if sa_validate_text_file_under_root "$APP_ROOT" "$binary"; then
    echo "FAIL: binary file accepted" >&2; exit 1
else
    [ "$?" -eq 65 ]
    [ "$SA_VALIDATE_FILE_REASON" = binary ]
fi

oversized="$APP_ROOT/oversized.php"
/usr/bin/truncate -s 262145 -- "$oversized"
if sa_validate_text_file_under_root "$APP_ROOT" "$oversized"; then
    echo "FAIL: oversized file accepted" >&2; exit 1
else
    [ "$?" -eq 75 ]
    [ "$SA_VALIDATE_FILE_REASON" = oversized ]
fi

link="$APP_ROOT/linked.php"
ln -s -- "$valid" "$link"
if sa_validate_text_file_under_root "$APP_ROOT" "$link"; then
    echo "FAIL: symlink accepted" >&2; exit 1
else
    [ "$?" -eq 64 ]
    [ "$SA_VALIDATE_FILE_REASON" = invalid_path ]
fi

mkdir "$APP_ROOT/subdir"
if sa_validate_text_file_under_root "$APP_ROOT" "$APP_ROOT/subdir"; then
    echo "FAIL: directory accepted as file" >&2; exit 1
else
    [ "$?" -eq 65 ]
    [ "$SA_VALIDATE_FILE_REASON" = not_regular_or_symlink ]
fi

if sa_validate_text_file_under_root "$APP_ROOT" "$valid/../outside.php"; then
    echo "FAIL: non-canonical path accepted" >&2; exit 1
else
    [ "$?" -eq 64 ]
    [ "$SA_VALIDATE_FILE_REASON" = invalid_path ]
fi

secret="$APP_ROOT/secret-canary.php"
canary='password=canary-must-not-be-logged'
printf '%s\n' '<?php' "$canary" > "$secret"
trace_out="$TMP/trace.out"
trace_err="$TMP/trace.err"
(
    set -x
    sa_validate_text_file_under_root "$APP_ROOT" "$secret" > "$trace_out" 2> "$trace_err"
    sa_validate_close_text_file
)
if /usr/bin/grep -Fq -- "$canary" "$trace_out" "$trace_err"; then
    echo "FAIL: canary leaked during xtrace preflight" >&2; exit 1
fi
[ ! -s "$trace_out" ]


pinned="$APP_ROOT/pinned.php"
printf '%s\n' 'original-content' > "$pinned"
sa_validate_text_file_under_root "$APP_ROOT" "$pinned"
pinned_fd=$SA_VALIDATE_FILE_FD
mv -- "$pinned" "$pinned.original"
printf '%s\n' 'replacement-content' > "$pinned"
IFS= read -r pinned_line < "/proc/$BASHPID/fd/$pinned_fd"
[ "$pinned_line" = original-content ]
sa_validate_close_text_file

parent_link="$TMP/root-link"
ln -s -- "$APP_ROOT" "$parent_link"
if sa_validate_text_file_under_root "$parent_link" "$parent_link/wp-config.php"; then
    echo "FAIL: symlinked root accepted" >&2; exit 1
else
    [ "$?" -eq 64 ]
    [ "$SA_VALIDATE_FILE_REASON" = invalid_path ]
fi

echo "text file validation tests: PASS"
