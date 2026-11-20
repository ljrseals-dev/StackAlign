#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# CLI-level plan, validation, and destructive-operation gate tests.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export SA_MYSQL_DEFAULTS_FILE="$TMP/mysql.cnf"
printf '[client]\nuser=test\npassword=not-a-real-secret\n' > "$TMP/mysql.cnf"
chmod 600 "$TMP/mysql.cnf"

plan=$(bash "$ROOT/bin/stackalign" db create webapp)
printf '%s\n' "$plan" | grep -q 'plan: would create database webapp'
printf '%s\n' "$plan" | grep -q 'no database state changed'

set +e
bash "$ROOT/bin/stackalign" db create 'webapp;touch /tmp/stackalign-db-pwned' >/dev/null 2>&1
bad_rc=$?
set -e
[ "$bad_rc" -eq 64 ]
[ ! -e /tmp/stackalign-db-pwned ]

set +e
bash "$ROOT/bin/stackalign" db drop webapp --apply >"$TMP/drop.out" 2>&1
drop_rc=$?
set -e
[ "$drop_rc" -eq 2 ]
grep -q 'DROP BLOCKED' "$TMP/drop.out"

echo "database CLI plan/validation/drop-gate tests: PASS"
