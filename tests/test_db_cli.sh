#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_db_cli.sh -- CLI plan/apply/list/drop-gate tests.
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
  case "$arg" in --execute=*) query=${arg#--execute=} ;; esac
done
case "$query" in
  'SHOW DATABASES;') printf 'mysql\napp_db\n' ;;
  SELECT*) ;;
  'CREATE DATABASE '*) printf '%s\n' "$query" >> "$TEST_TMP/create.log" ;;
  *) echo "unexpected query: $query" >&2; exit 64 ;;
esac
EOF
chmod 700 "$TMP/bin/mysql"

plan=$(bash "$ROOT/bin/stackalign" db create webapp)
printf '%s\n' "$plan" | grep -q 'plan: would create database webapp'
[ ! -e "$TMP/create.log" ]

bash "$ROOT/bin/stackalign" db create webapp --apply
grep -q 'CREATE DATABASE \`webapp\`' "$TMP/create.log"
bash "$ROOT/bin/stackalign" db list | grep -q 'app_db'

set +e
bash "$ROOT/bin/stackalign" db drop webapp --apply >"$TMP/drop.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -q 'DROP BLOCKED' "$TMP/drop.out"
if grep -q 'DROP DATABASE' "$TMP/create.log"; then
  echo "FAIL: drop reached the SQL client" >&2; exit 1
fi

echo "database CLI tests: PASS"
