#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
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
  'SELECT VERSION(), CURRENT_USER();') printf '10.11.6-MariaDB\tstackalign@localhost\n' ;;
  'SELECT User, Host FROM mysql.user ORDER BY User, Host;') printf 'stackalign\tlocalhost\nroot\tlocalhost\n' ;;
  'SELECT @@version_comment, @@version, @@port, @@socket, @@bind_address;')
    case "${FAKE_DISCOVER_MODE:-mariadb}" in
      mariadb) printf 'MariaDB Server\t10.11.6-MariaDB\t3306\t/var/lib/mysql/mysql.sock\t127.0.0.1\n' ;;
      mysql) printf 'MySQL Community Server - GPL\t8.0.36\t3307\t/var/lib/mysql/mysql.sock\t127.0.0.1\n' ;;
      percona) printf 'Percona Server (GPL), Release 27\t8.0.35-27\t3306\t/var/lib/mysql/mysql.sock\t*\n' ;;
      unknown) printf 'Unrecognized vendor\t8.0.0\tNULL\t\tNULL\n' ;;
      badvar) echo "Unknown system variable 'bind_address'" >&2; exit 1 ;;
      fail) echo 'Access denied password=hunter2' >&2; exit 1 ;;
      *) echo "unexpected discovery mode" >&2; exit 64 ;;
    esac ;;
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
_sa_db_client_available() { [ -x "$TMP/bin/mysql" ]; }

# Test-only dependency injection: production sa_exec remains absolute-path only.
sa_exec() {
  local tool=$1
  shift
  [ "${1-}" = -- ] && shift
  "$TMP/bin/$tool" "$@"
}
listing=$(sa_db_list)
printf '%s\n' "$listing" | grep -q 'app_db'
status=$(sa_db_status)
printf '%s\n' "$status" | grep -q 'server_version: 10.11.6-MariaDB'
printf '%s\n' "$status" | grep -q 'authenticated_account: stackalign@localhost'
users=$(sa_db_user_list)
printf '%s\n' "$users" | grep -q 'stackalign'

discovery=$(sa_db_discover)
printf '%s\n' "$discovery" | grep -q '^engine: MariaDB

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$discovery" | grep -q '^distribution: MariaDB Server

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$discovery" | grep -q '^version: 10.11.6-MariaDB

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$discovery" | grep -q '^server_port: 3306

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$discovery" | grep -q '^configured_bind_address: 127.0.0.1

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$discovery" | grep -q '^actual_listener: UNKNOWN

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

! printf '%s\n' "$discovery" | grep -q 'not-a-real-secret'

mysql_discovery=$(FAKE_DISCOVER_MODE=mysql sa_db_discover)
printf '%s\n' "$mysql_discovery" | grep -q '^engine: MySQL

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$mysql_discovery" | grep -q '^distribution: MySQL Community Server - GPL

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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


percona_discovery=$(FAKE_DISCOVER_MODE=percona sa_db_discover)
printf '%s\n' "$percona_discovery" | grep -q '^engine: MySQL

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$percona_discovery" | grep -q '^distribution: Percona Server

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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


unknown_discovery=$(FAKE_DISCOVER_MODE=unknown sa_db_discover)
printf '%s\n' "$unknown_discovery" | grep -q '^engine: UNKNOWN

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$unknown_discovery" | grep -q '^distribution: UNKNOWN

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$unknown_discovery" | grep -q '^server_port: UNKNOWN

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$unknown_discovery" | grep -q '^server_socket: UNKNOWN

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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

printf '%s\n' "$unknown_discovery" | grep -q '^configured_bind_address: UNKNOWN

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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


for mode in badvar fail; do
    if output=$(FAKE_DISCOVER_MODE="$mode" sa_db_discover 2>"$TMP/$mode.err"); then
        echo "FAIL: discovery mode $mode unexpectedly succeeded" >&2; exit 1
    fi
    [ -z "$output" ]
    grep -Fxq 'db: discovery query failed' "$TMP/$mode.err"
    [ "$(wc -l < "$TMP/$mode.err")" -eq 1 ]
    ! grep -Eiq 'hunter2|access denied|unknown system variable|password=' "$TMP/$mode.err"
done

sa_db_create app_db
grep -Fq 'CREATE DATABASE IF NOT EXISTS `app_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "$TMP/sql.log"
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
