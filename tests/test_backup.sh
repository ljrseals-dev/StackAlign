#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_backup.sh -- isolated helper tests; no live database is contacted.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -m 700 "$TMP/bin" "$TMP/backups"
printf '[client]\nuser=test\npassword=not-a-real-secret\n' > "$TMP/mysql.cnf"
chmod 600 "$TMP/mysql.cnf"
export SA_MYSQL_DEFAULTS_FILE="$TMP/mysql.cnf"
export PATH="$TMP/bin:$PATH"

cat > "$TMP/bin/mysqldump" <<'EOF'
#!/usr/bin/env bash
printf 'CREATE DATABASE test_db;\n'
EOF
chmod 700 "$TMP/bin/mysqldump"

cat > "$TMP/bin/mariabackup" <<'EOF'
#!/usr/bin/env bash
target=''
mode=''
for arg in "$@"; do
  case "$arg" in
    --target-dir=*) target=\${arg#--target-dir=} ;;
    --backup) mode=backup ;;
    --prepare) mode=prepare ;;
  esac
done
[ -n "$target" ] || exit 64
if [ "$mode" = backup ]; then
  mkdir -p "$target"
  printf 'backup_type = full-backuped\n' > "$target/xtrabackup_checkpoints"
elif [ "$mode" = prepare ]; then
  printf 'backup_type = full-prepared\n' > "$target/xtrabackup_checkpoints"
else
  exit 64
fi
EOF
chmod 700 "$TMP/bin/mariabackup"

source "$ROOT/lib/backup.sh"
logical=$(sa_backup_dump "$TMP/backups")
[ -f "$logical" ] && [ ! -L "$logical" ]
[ "$(stat -c '%a' "$logical")" = 600 ]
sa_backup_verify "$logical" | grep -q 'gzip container integrity'
gzip -t "$logical"

cp "$logical" "$TMP/backups/db-corrupt.sql.gz"
printf 'corruption' >> "$TMP/backups/db-corrupt.sql.gz"
if sa_backup_verify "$TMP/backups/db-corrupt.sql.gz" >/dev/null 2>&1; then
  echo "FAIL: corrupt gzip accepted" >&2; exit 1
fi
ln -s "$logical" "$TMP/backups/db-link.sql.gz"
if sa_backup_verify "$TMP/backups/db-link.sql.gz" >/dev/null 2>&1; then
  echo "FAIL: symlink artifact accepted" >&2; exit 1
fi

physical="$TMP/backups/mariadb-test"
sa_backup_physical "$physical" >/dev/null
sa_backup_verify "$physical" | grep -q 'prepared checkpoint'
if sa_backup_physical "$physical" >/dev/null 2>&1; then
  echo "FAIL: existing physical target overwritten" >&2; exit 1
fi

listing=$(sa_backup_list "$TMP/backups")
printf '%s\n' "$listing" | grep -q 'logical'
printf '%s\n' "$listing" | grep -q 'physical'

chmod 644 "$TMP/mysql.cnf"
if sa_backup_dump "$TMP/backups" >/dev/null 2>&1; then
  echo "FAIL: world-readable defaults file accepted" >&2; exit 1
fi

echo "backup tests: PASS"
