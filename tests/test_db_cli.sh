#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
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

for args in "extra" "--apply"; do
    if [ "$args" = extra ]; then
        set +e
        bash "$ROOT/bin/stackalign" db discover extra >"$TMP/discover.out" 2>&1
        discover_rc=$?
        set -e
    else
        set +e
        bash "$ROOT/bin/stackalign" db discover --apply >"$TMP/discover.out" 2>&1
        discover_rc=$?
        set -e
    fi
    [ "$discover_rc" -eq 64 ]
    grep -Fxq 'stackalign: usage: stackalign db discover' "$TMP/discover.out"
done

help_db=$(bash "$ROOT/bin/stackalign" help db)
printf '%s\n' "$help_db" | grep -q 'discover'

set +e
bash "$ROOT/bin/stackalign" db unknown >"$TMP/unknown-db.out" 2>&1
unknown_db_rc=$?
set -e
[ "$unknown_db_rc" -eq 64 ]
grep -Fq 'status|discover|applications|list|user list' "$TMP/unknown-db.out"

wp_config="$TMP/wp-config.php"
wp_canary='password=cli-canary-must-not-print'
wp_user='private-cli-user-must-not-print'
printf '%s\n' '<?php' "define('DB_NAME', 'cli_wordpress');" "define('DB_HOST', 'localhost:3306');" "define('DB_USER', '$wp_user');" "define('DB_PASSWORD', '$wp_canary');" "require_once ABSPATH . 'wp-settings.php';" > "$wp_config"

app_output=$(bash "$ROOT/bin/stackalign" db applications --root "$TMP" --wordpress "$wp_config")
printf '%s\n' "$app_output" | grep -Fq 'app_db_name: cli_wordpress'
printf '%s\n' "$app_output" | grep -Fq 'app_db_host: localhost'
printf '%s\n' "$app_output" | grep -Fq 'app_db_port: 3306'
printf '%s\n' "$app_output" | grep -Fq 'app_db_user: PRESENT'
printf '%s\n' "$app_output" | grep -Fq 'application_connection: UNKNOWN'
if printf '%s\n' "$app_output" | grep -Fq "$wp_user" || printf '%s\n' "$app_output" | grep -Fq "$wp_canary"; then
    echo "FAIL: application CLI disclosed credentials" >&2; exit 1
fi

plan_output=$(bash "$ROOT/bin/stackalign" --plan db applications --root "$TMP" --wordpress "$wp_config")
printf '%s\n' "$plan_output" | grep -Fq 'app_db_name: cli_wordpress'

for mode in missing_root missing_wordpress apply extra; do
    case "$mode" in
        missing_root)
            set +e
            bash "$ROOT/bin/stackalign" db applications --wordpress "$wp_config" >"$TMP/app-cli.out" 2>&1
            app_rc=$?
            set -e ;;
        missing_wordpress)
            set +e
            bash "$ROOT/bin/stackalign" db applications --root "$TMP" >"$TMP/app-cli.out" 2>&1
            app_rc=$?
            set -e ;;
        apply)
            set +e
            bash "$ROOT/bin/stackalign" db applications --root "$TMP" --wordpress "$wp_config" --apply >"$TMP/app-cli.out" 2>&1
            app_rc=$?
            set -e ;;
        extra)
            set +e
            bash "$ROOT/bin/stackalign" db applications --root "$TMP" --wordpress "$wp_config" extra >"$TMP/app-cli.out" 2>&1
            app_rc=$?
            set -e ;;
    esac
    [ "$app_rc" -eq 64 ]
    grep -Fq 'usage: stackalign db applications' "$TMP/app-cli.out"
done

help_db=$(bash "$ROOT/bin/stackalign" help db)
printf '%s\n' "$help_db" | grep -q 'applications --root'
echo "database CLI plan/validation/drop-gate tests: PASS"
