#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v sqlite3 >/dev/null 2>&1 || { echo "state tests: sqlite3 missing" >&2; exit 69; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -m 700 "$TMP/state"
export SA_STATE_DB="$TMP/state/state.db" SA_ROOT="$ROOT"
source "$ROOT/lib/state.sh"
sa_state_init
[[ $(stat -c '%a' "$SA_STATE_DB") == 600 ]]
[[ $(sqlite3 "$SA_STATE_DB" 'SELECT version FROM schema_migrations;') == 1 ]]
sa_state_init >/dev/null
[[ $(sqlite3 "$SA_STATE_DB" 'SELECT count(*) FROM schema_migrations;') == 1 ]]
id=$(sa_task_create health_check "Operator's initial server inspection")
[[ $id =~ ^[0-9a-f-]{36}$ ]]
[[ $(sqlite3 "$SA_STATE_DB" "SELECT status FROM tasks WHERE id='$id';") == pending ]]
sa_task_transition "$id" running 'Started by operator' >/dev/null
sa_task_transition "$id" succeeded 'All checks passed' >/dev/null
[[ $(sqlite3 "$SA_STATE_DB" "SELECT status FROM tasks WHERE id='$id';") == succeeded ]]
[[ $(sqlite3 "$SA_STATE_DB" "SELECT count(*) FROM task_events WHERE task_id='$id';") == 3 ]]
if sa_task_transition "$id" running >/dev/null 2>&1; then echo "FAIL: terminal task restarted" >&2; exit 1; fi
if sa_task_create shell_command 'arbitrary command' >/dev/null 2>&1; then echo "FAIL: unknown task type accepted" >&2; exit 1; fi
if sa_task_create health_check '' >/dev/null 2>&1; then echo "FAIL: empty description accepted" >&2; exit 1; fi
tab=$(printf '\011')
if sa_task_create health_check "bad${tab}field" >/dev/null 2>&1; then echo "FAIL: task description accepted terminal control characters" >&2; exit 1; fi
pending_id=$(sa_task_create health_check "Control-character rejection test")
newline=$(printf '\012X'); newline=${newline%X}
if sa_task_transition "$pending_id" running "bad${newline}field" >/dev/null 2>&1; then echo "FAIL: task event detail accepted terminal control characters" >&2; exit 1; fi
[[ $(sqlite3 "$SA_STATE_DB" "SELECT status FROM tasks WHERE id='$pending_id';") == pending ]]
[[ $(sqlite3 "$SA_STATE_DB" 'PRAGMA integrity_check;') == ok ]]

# Every task operation must enforce the same owner-only database boundary.
chmod 0644 "$SA_STATE_DB"
if sa_task_list >/dev/null 2>&1; then echo "FAIL: task list accepted a world-readable database" >&2; exit 1; fi
if sa_task_transition "$id" failed "must not write" >/dev/null 2>&1; then echo "FAIL: task transition accepted a world-readable database" >&2; exit 1; fi
if sa_task_create health_check "must not write" >/dev/null 2>&1; then echo "FAIL: task create accepted a world-readable database" >&2; exit 1; fi
chmod 0600 "$SA_STATE_DB"
[[ $(sqlite3 "$SA_STATE_DB" "SELECT status FROM tasks WHERE id='$id';") == succeeded ]]
echo "state database permissions enforced for list, transition, and create"

echo "state database and task lifecycle tests: PASS"
