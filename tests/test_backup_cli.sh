#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_backup_cli.sh -- CLI plan/apply/list/verify and restore gate tests.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -m 700 "$TMP/bin"
printf '[client]\nuser=test\npassword=not-a-real-secret\n' > "$TMP/mysql.cnf"
chmod 600 "$TMP/mysql.cnf"
export SA_MYSQL_DEFAULTS_FILE="$TMP/mysql.cnf"
export PATH="$TMP/bin:$PATH"

cat > "$TMP/bin/mysqldump" <<'EOF'
#!/usr/bin/env bash
printf 'CREATE DATABASE cli_test;\n'
EOF
chmod 700 "$TMP/bin/mysqldump"

out=$(bash "$ROOT/bin/stackalign" backup run logical "$TMP/backups")
printf '%s\n' "$out" | grep -q 'plan: would create'
[ ! -e "$TMP/backups" ]

file=$(bash "$ROOT/bin/stackalign" backup run logical "$TMP/backups" --apply)
[ -f "$file" ]
bash "$ROOT/bin/stackalign" backup verify "$file" | grep -q 'gzip container integrity'
bash "$ROOT/bin/stackalign" backup list "$TMP/backups" | grep -q 'logical'

# Restore planning verifies the artifact and credential boundary without invoking mysql.
cat > "$TMP/bin/mysql" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: restore preflight invoked mysql" >&2
exit 99
EOF
chmod 700 "$TMP/bin/mysql"
plan=$(bash "$ROOT/bin/stackalign" restore --from "$file" --plan)
printf '%s\\n' "$plan" | grep -q 'LOGICAL RESTORE PREFLIGHT'
printf '%s\\n' "$plan" | grep -q 'all-databases dump'
printf '%s\\n' "$plan" | grep -q 'no database changes made'
if bash "$ROOT/bin/stackalign" restore --from "$TMP/missing.sql.gz" --plan >/dev/null 2>&1; then
  echo "FAIL: missing restore artifact accepted" >&2; exit 1
fi

set +e
bash "$ROOT/bin/stackalign" restore --from "$file" --apply >"$TMP/restore.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -q 'BLOCKED' "$TMP/restore.out"
grep -q 'no database changes made' "$TMP/restore.out"

echo "backup CLI tests: PASS"
