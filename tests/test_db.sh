#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_db.sh -- isolated MariaDB helper tests; no live server is contacted.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -m 700 "$TMP/bin"
printf '[client]\nuser=test\npassword=not-a-real-secret\n' > "$TMP/mysql.cnf"
chmod 600 "$TMP/mysql.cnf"
export SA_MYSQL_DEFAULTS_FILE="$TMP/mysql.cnf"
export TEST_TMP="$TMP"
export PATH="$TMP/bin:$PATH"

cat > "$TMP/bin/mysql" <<'EOF'
#!/usr/bin/env bash
query=''
for arg in "$@"; do
  case "$arg" in
    --execute=*) query=${arg#--execute=} ;;
  esac
done
case "$query" in
  'SHOW DATABASES;')
    printf 'information_schema\nmysql\napp_db\n' ;;
  SELECT*)
    if [ "${FAKE_DB_EXISTS:-0}" = 1 ]; then printf 'app_db\n'; fi ;;
  'CREATE DATABASE '*)
    printf '%s\n' "$query" >> "$TEST_TMP/sql.log" ;;
  'DROP DATABASE '*)
    echo "FAIL: drop query reached mysql" >&2; exit 90 ;;
  *) echo "unexpected query: $query" >&2; exit 64 ;;
esac
EOF
chmod 700 "$TMP/bin/mysql"

source "$ROOT/lib/db.sh"
listing=$(sa_db_list)
printf '%s\n' "$listing" | grep -q 'app_db'

sa_db_create app_db
grep -q 'CREATE DATABASE IF NOT EXISTS \`app_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
before=$(wc -l < "$TMP/sql.log")
FAKE_DB_EXISTS=1 sa_db_create app_db | grep -q 'already exists'
after=$(wc -l < "$TMP/sql.log")
[ "$before" -eq "$after" ]

for bad in 'bad-name' 'x;DROP' '1leading' 'mysql' 'INFORMATION_SCHEMA' ''; do
  if sa_db_validate_name "$bad" >/dev/null 2>&1; then
    echo "FAIL: unsafe database name accepted: $bad" >&2; exit 1
  fi
done

chmod 644 "$TMP/mysql.cnf"
if sa_db_list >/dev/null 2>&1; then
  echo "FAIL: world-readable defaults file accepted" >&2; exit 1
fi

echo "database helper tests: PASS"
