#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_db_security.sh -- credential-file and mysql argument boundaries.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -m 700 "$TMP/bin"
printf '[client]\nuser=stackalign\npassword=fixture-secret-must-not-be-an-argument\n' > "$TMP/mysql.cnf"
chmod 600 "$TMP/mysql.cnf"
export TEST_TMP="$TMP"
export PATH="$TMP/bin:$PATH"

cat > "$TMP/bin/mysql" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$TEST_TMP/mysql.args"
for arg in "$@"; do
  case "$arg" in
    --execute='SHOW DATABASES;') printf 'app_db\n'; exit 0 ;;
  esac
done
exit 64
EOF
chmod 700 "$TMP/bin/mysql"
source "$ROOT/lib/db.sh"

# Valid credentials are passed through the protected defaults file, never argv.
export SA_MYSQL_DEFAULTS_FILE="$TMP/mysql.cnf"
sa_db_list | grep -q app_db
first_arg=$(head -n 1 "$TMP/mysql.args")
[ "$first_arg" = "--defaults-extra-file=$TMP/mysql.cnf" ]
if grep -Fq 'fixture-secret-must-not-be-an-argument' "$TMP/mysql.args"; then
  echo 'FAIL: database password appeared in mysql arguments' >&2; exit 1
fi

# Symlinks and group/world-readable files are rejected before invoking mysql.
: > "$TMP/mysql.args"
ln -s "$TMP/mysql.cnf" "$TMP/mysql-link.cnf"
SA_MYSQL_DEFAULTS_FILE="$TMP/mysql-link.cnf"
export SA_MYSQL_DEFAULTS_FILE
if sa_db_list >/dev/null 2>&1; then echo 'FAIL: symlink defaults file accepted' >&2; exit 1; fi
[ ! -s "$TMP/mysql.args" ]

for mode in 640 644 660 666 700; do
  chmod "$mode" "$TMP/mysql.cnf"
  SA_MYSQL_DEFAULTS_FILE="$TMP/mysql.cnf"
  export SA_MYSQL_DEFAULTS_FILE
  if sa_db_list >/dev/null 2>&1; then
    echo "FAIL: defaults file mode $mode accepted" >&2; exit 1
  fi
  [ ! -s "$TMP/mysql.args" ]
done

chmod 600 "$TMP/mysql.cnf"
SA_MYSQL_DEFAULTS_FILE=relative.cnf
export SA_MYSQL_DEFAULTS_FILE
if sa_db_list >/dev/null 2>&1; then echo 'FAIL: relative defaults path accepted' >&2; exit 1; fi
[ ! -s "$TMP/mysql.args" ]

SA_MYSQL_DEFAULTS_FILE="$TMP/missing.cnf"
export SA_MYSQL_DEFAULTS_FILE
if sa_db_list >/dev/null 2>&1; then echo 'FAIL: missing defaults file accepted' >&2; exit 1; fi
[ ! -s "$TMP/mysql.args" ]

echo 'database credential boundary tests: PASS'
