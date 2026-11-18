#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/state.sh -- local SQLite state store and deterministic task lifecycle.
_sa_state_db_path() {
  SA_STATE_DB=${SA_STATE_DB:-/var/lib/stackalign/state.db}
  [[ $SA_STATE_DB == /* && $SA_STATE_DB != *$'\n'* ]] || { echo "state: database path must be absolute" >&2; return 64; }
  local parent
  parent=$(dirname -- "$SA_STATE_DB")
  [[ -d $parent && ! -L $parent && $(realpath -e -- "$parent") == "$parent" ]] || { echo "state: parent must be an existing, resolved, non-symlink directory" >&2; return 1; }
  [[ ! -L $SA_STATE_DB ]] || { echo "state: database symlink refused" >&2; return 1; }
  export SA_STATE_DB
}
_sa_state_require_sqlite() {
  command -v sqlite3 >/dev/null 2>&1 || { echo "state: sqlite3 is required" >&2; return 69; }
}
_sa_state_sql_quote() { local v=${1-}; v=${v//\'/\'\'}; printf "'%s'" "$v"; }
_sa_state_exec() { (umask 077; sqlite3 -batch -bail -noheader -cmd '.timeout 5000' "$SA_STATE_DB" "$1"); }

_sa_state_existing_db() {
  [[ -f $SA_STATE_DB && ! -L $SA_STATE_DB ]] || { echo "state: database is missing or not a regular file" >&2; return 1; }
  local mode owner
  read -r mode owner < <(stat -c '%a %u' -- "$SA_STATE_DB") || return 1
  [[ $owner == "$(id -u)" && ( $mode == 600 || $mode == 400 ) ]] || { echo "state: database must be owned by this user with mode 600 or 400" >&2; return 1; }
}
sa_state_init() {
  _sa_state_require_sqlite || return $?
  _sa_state_db_path || return $?
  local schema="$SA_ROOT/schema/001-initial.sql" created=0
  [[ -f $schema && ! -L $schema ]] || { echo "state: schema missing or unsafe" >&2; return 1; }
  if [[ ! -e $SA_STATE_DB ]]; then
    (umask 077; set -o noclobber; : > "$SA_STATE_DB") 2>/dev/null || { echo "state: cannot create database" >&2; return 1; }
    created=1
  else
    [[ -f $SA_STATE_DB ]] || { echo "state: database is not a regular file" >&2; return 1; }
    local mode owner
    read -r mode owner < <(stat -c '%a %u' -- "$SA_STATE_DB") || return 1
    [[ $owner == "$(id -u)" && ( $mode == 600 || $mode == 400 ) ]] || { echo "state: existing database must be owned by this user with mode 600 or 400" >&2; return 1; }
  fi
  chmod 600 -- "$SA_STATE_DB" || return 1
  if ! (umask 077; sqlite3 -batch -bail -cmd '.timeout 5000' "$SA_STATE_DB" < "$schema"); then
    echo "state: migration failed" >&2
    [[ $created == 1 ]] && rm -f -- "$SA_STATE_DB"
    return 1
  fi
  chmod 600 -- "$SA_STATE_DB" || return 1
  printf 'state database ready: %s\n' "$SA_STATE_DB"
}
sa_state_status() {
  _sa_state_require_sqlite || return $?
  _sa_state_db_path || return $?
  _sa_state_existing_db || { echo "state: not initialized or unsafe; run state init --apply" >&2; return 1; }
  local version counts
  version=$(_sa_state_exec "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1;") || return $?
  counts=$(_sa_state_exec "SELECT status || ':' || count(*) FROM tasks GROUP BY status ORDER BY status;") || return $?
  printf 'database: %s\nschema_version: %s\ntasks:\n%s\n' "$SA_STATE_DB" "$version" "${counts:-none}"
}
sa_task_create() {
  local kind=${1:-} description=${2:-} id qid qkind qdesc
  case "$kind" in health_check|website_deploy|database_backup|website_migration) ;; *) echo "task: unsupported type: $kind" >&2; return 64 ;; esac
  [[ -n $description && ${#description} -le 500 ]] || { echo "task: description must contain 1-500 characters" >&2; return 64; }
  _sa_state_db_path || return $?
  _sa_state_existing_db || { echo "task: state database is not initialized or has unsafe permissions" >&2; return 1; }
  id=$(< /proc/sys/kernel/random/uuid) || return 1
  qid=$(_sa_state_sql_quote "$id"); qkind=$(_sa_state_sql_quote "$kind"); qdesc=$(_sa_state_sql_quote "$description")
  _sa_state_exec "BEGIN IMMEDIATE;
INSERT INTO tasks(id,task_type,description,status,created_at,updated_at) VALUES($qid,$qkind,$qdesc,'pending',strftime('%Y-%m-%dT%H:%M:%fZ','now'),strftime('%Y-%m-%dT%H:%M:%fZ','now'));
INSERT INTO task_events(task_id,event_type,detail,created_at) VALUES($qid,'created',$qdesc,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
COMMIT;" || return $?
  printf '%s\n' "$id"
}
sa_task_list() {
  _sa_state_db_path || return $?
  [[ -f $SA_STATE_DB && ! -L $SA_STATE_DB ]] || { echo "task: state database is not initialized" >&2; return 1; }
  _sa_state_exec "SELECT id || char(9) || task_type || char(9) || status || char(9) || description FROM tasks ORDER BY created_at DESC,id;"
}
sa_task_transition() {
  local id=${1:-} target=${2:-} detail=${3:-} qid qdetail expected result
  [[ $id =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "task: invalid task id" >&2; return 64; }
  case "$target" in running) expected=pending ;; succeeded|failed) expected=running ;; *) return 64 ;; esac
  [[ ${#detail} -le 500 ]] || { echo "task: detail exceeds 500 characters" >&2; return 64; }
  _sa_state_db_path || return $?
  [[ -f $SA_STATE_DB && ! -L $SA_STATE_DB ]] || { echo "task: state database is not initialized" >&2; return 1; }
  qid=$(_sa_state_sql_quote "$id"); qdetail=$(_sa_state_sql_quote "$detail")
  result=$(_sa_state_exec "BEGIN IMMEDIATE;
CREATE TEMP TABLE _sa_transition_result(changed INTEGER);
UPDATE tasks SET status='$target',updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=$qid AND status='$expected';
INSERT INTO _sa_transition_result VALUES(changes());
INSERT INTO task_events(task_id,event_type,detail,created_at)
 SELECT $qid,'$target',$qdetail,strftime('%Y-%m-%dT%H:%M:%fZ','now')
 WHERE (SELECT changed FROM _sa_transition_result)=1;
SELECT changed FROM _sa_transition_result;
DROP TABLE _sa_transition_result;
COMMIT;") || return $?
  [[ $result == 1 ]] || { echo "task: transition refused (missing task or invalid current state)" >&2; return 1; }
  printf 'task %s: %s\n' "$id" "$target"
}
