#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
# tests/test_applications.sh -- WordPress-only static inventory fixtures.
set -euo pipefail
trap 'printf "test_applications: failure at line %s\\n" "$LINENO" >&2' ERR

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(/usr/bin/mktemp -d)
trap '/usr/bin/rm -rf -- "$TMP"' EXIT
mkdir -m 700 "$TMP/root"
APP_ROOT=$(cd "$TMP/root" && pwd -P)

source "$ROOT/lib/applications.sh"

valid="$APP_ROOT/wp-config.php"
printf '%s\n' '<?php' "define('DB_NAME', 'wordpress');" "define('DB_HOST', 'localhost:3307');" '?>' > "$valid"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$valid")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'status: INVENTORIED'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'effective_config: CONFIRMED'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_name: wordpress'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_name_confidence: CONFIRMED'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_host: localhost'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_port: 3307'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'application_connection: UNKNOWN'
if printf '%s\n' "$result" | /usr/bin/grep -Fq 'matches_server:'; then
    echo "FAIL: v1 emitted deferred server matching" >&2; exit 1
fi

double="$APP_ROOT/double-quoted.php"
printf '%s\n' '<?php' 'define("DB_NAME", "wordpress2");' 'define("DB_HOST", "[::1]:3306");' '?>' > "$double"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$double")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_name: wordpress2'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_host: ::1'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_port: 3306'

socket="$APP_ROOT/socket.php"
printf '%s\n' '<?php' "define('DB_HOST', ':/run/mysqld/mysqld.sock');" '?>' > "$socket"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$socket")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_host: UNKNOWN'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_socket: /run/mysqld/mysqld.sock'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_socket_confidence: CONFIRMED'

host_socket="$APP_ROOT/host-socket.php"
printf '%s\n' '<?php' "define('DB_HOST', 'localhost:/run/mysqld/mysqld.sock');" '?>' > "$host_socket"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$host_socket")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_host: localhost'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_socket: /run/mysqld/mysqld.sock'

dynamic="$APP_ROOT/dynamic.php"
printf '%s\n' '<?php' "define('DB_NAME', getenv('DB_NAME'));" "define('DB_HOST', 'localhost');" '?>' > "$dynamic"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$dynamic")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_name: UNKNOWN'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_name_confidence: UNKNOWN'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'effective_config: UNKNOWN'

included="$APP_ROOT/included.php"
printf '%s\n' '<?php' '!include /etc/wordpress/database.conf' "define('DB_NAME', 'wordpress');" '?>' > "$included"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$included")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'effective_config: UNKNOWN'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_name: wordpress'

malformed="$APP_ROOT/malformed.php"
printf '%s\n' '<?php' "define('DB_NAME'," "'wordpress');" '?>' > "$malformed"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$malformed")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_name: UNKNOWN'

duplicate="$APP_ROOT/duplicate.php"
printf '%s\n' '<?php' "define('DB_NAME', 'one');" "define('DB_NAME', 'two');" '?>' > "$duplicate"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$duplicate")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_name: UNKNOWN'

user_secret="$APP_ROOT/user-secret.php"
canary='password=canary-never-output'
username='private-wp-user-must-not-output'
printf '%s\n' '<?php' "define('DB_NAME', 'wordpress');" "define('DB_HOST', 'db.internal');" "define('DB_USER', '$username');" "define('DB_PASSWORD', '$canary');" "require_once ABSPATH . 'wp-settings.php';" > "$user_secret"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$user_secret")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_user: PRESENT'
if printf '%s\n' "$result" | /usr/bin/grep -Fq "$username"; then
    echo "FAIL: database username was printed" >&2; exit 1
fi
if printf '%s\n' "$result" | /usr/bin/grep -Fq "$canary"; then
    echo "FAIL: password canary was printed" >&2; exit 1
fi
printf '%s\n' "$result" | /usr/bin/grep -Fq 'effective_config: UNKNOWN'

secret_host="$APP_ROOT/secret-host.php"
printf '%s\n' '<?php' "define('DB_HOST', 'auth.example.com');" '?>' > "$secret_host"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$secret_host")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'app_db_host: UNKNOWN'

missing="$APP_ROOT/missing.php"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$missing")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'status: UNKNOWN'
printf '%s\n' "$result" | /usr/bin/grep -Fq 'reason: missing'

binary="$APP_ROOT/binary.php"
printf 'prefix\000suffix\n' > "$binary"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$binary")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'reason: binary'

oversized="$APP_ROOT/oversized.php"
/usr/bin/truncate -s 262145 -- "$oversized"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$oversized")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'reason: oversized'

symlink="$APP_ROOT/symlink.php"
ln -s -- "$valid" "$symlink"
result=$(sa_db_parse_wordpress_config "$APP_ROOT" "$symlink")
printf '%s\n' "$result" | /usr/bin/grep -Fq 'reason: invalid_path'

trace_out="$TMP/trace.out"
trace_err="$TMP/trace.err"
(
    set -x
    sa_db_parse_wordpress_config "$APP_ROOT" "$user_secret"
) > "$trace_out" 2> "$trace_err"
if /usr/bin/grep -Fq -- "$canary" "$trace_out" "$trace_err" ||
   /usr/bin/grep -Fq -- "$username" "$trace_out" "$trace_err"; then
    echo "FAIL: secret or username leaked under xtrace" >&2; exit 1
fi
canary_hex=$(/usr/bin/printf '%s' "$canary" | /usr/bin/od -An -v -t x1 | /usr/bin/tr -d '[:space:]')
username_hex=$(/usr/bin/printf '%s' "$username" | /usr/bin/od -An -v -t x1 | /usr/bin/tr -d '[:space:]')
trace_hex=$(/usr/bin/tr -d '[:space:]' < "$trace_err")
if [[ $trace_hex == *"$canary_hex"* || $trace_hex == *"$username_hex"* ]]; then
    echo "FAIL: reversible secret bytes leaked under xtrace" >&2; exit 1
fi

echo "WordPress application inventory tests: PASS"
