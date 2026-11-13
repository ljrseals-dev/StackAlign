#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export SA_HISTORY_ROOT="$T/hist" SA_SECRETS_DIR="$T/etc/secrets"
source "$ROOT/lib/history.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }

mkdir -p "$T/etc/secrets" "$T/etc/conf.d"
printf 'v1\n' > "$T/etc/a.conf"
printf 'one\n' > "$T/etc/conf.d/x"; printf 'two\n' > "$T/etc/conf.d/y"
printf 'k\n' > "$T/etc/secrets/key"

# file snapshot + rollback restores bytes
id=$(sa_history_snapshot "$T/etc/a.conf" edit); printf 'v2\n' > "$T/etc/a.conf"
sa_history_rollback "$id"
[ "$(cat "$T/etc/a.conf")" = v1 ] && ok "file rollback restores bytes" || bad "file rollback restores bytes"

# directory snapshot + rollback
id=$(sa_history_snapshot "$T/etc/conf.d" dir); rm "$T/etc/conf.d/x"; printf 'zzz\n' > "$T/etc/conf.d/new"
sa_history_rollback "$id"
{ [ "$(cat "$T/etc/conf.d/x")" = one ] && [ ! -e "$T/etc/conf.d/new" ]; } && ok "directory rollback" || bad "directory rollback"

# snapshot of a nonexistent path: rollback removes what was created later
id=$(sa_history_snapshot "$T/etc/new.conf" create); printf 'made\n' > "$T/etc/new.conf"
sa_history_rollback "$id"
[ ! -e "$T/etc/new.conf" ] && ok "rollback removes file that did not exist" || bad "rollback removes file that did not exist"

# secrets refusal, and override warns
sa_history_snapshot "$T/etc/secrets/key" s >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && ok "secrets path refused" || bad "secrets path refused"
w=$(SA_HISTORY_ALLOW_SECRETS=1 sa_history_snapshot "$T/etc/secrets/key" s 2>&1 >/dev/null)
case $w in *WARNING*) ok "override warns on stderr" ;; *) bad "override warns on stderr" ;; esac

# idempotent within the same second for the same path+slug
a=$(sa_history_snapshot "$T/etc/a.conf" same); b=$(sa_history_snapshot "$T/etc/a.conf" same)
if [ "$a" = "$b" ]; then ok "idempotent same path+slug"; else
  # may straddle a second boundary; retry once
  a=$(sa_history_snapshot "$T/etc/a.conf" same2); b=$(sa_history_snapshot "$T/etc/a.conf" same2)
  [ "$a" = "$b" ] && ok "idempotent same path+slug (retry)" || bad "idempotent same path+slug"
fi

# list + path + undo.sh exists
n=$(sa_history_list | wc -l)
[ "$n" -ge 3 ] && ok "list works ($n entries)" || bad "list works"
[ -x "$(sa_history_path "$id")/undo.sh" ] && ok "undo.sh generated" || bad "undo.sh generated"

# Exercise generated PID-scoped stage/backup names, including repeated undo.
root="$T/undo-pid"
mkdir -p "$root"
printf 'v1\n' > "$root/target.conf"
pid_id=$(sa_history_snapshot "$root/target.conf" pidtemps)
pid_undo="$SA_HISTORY_ROOT/$pid_id/undo.sh"
rc=0
grep -Fq 'stackalign-new.$$' "$pid_undo" || rc=1
grep -Fq 'stackalign-old.$$' "$pid_undo" || rc=1
if grep -Fq 'stackalign-new.$"' "$pid_undo" || grep -Fq 'stackalign-old.$"' "$pid_undo"; then rc=1; fi
printf 'v2\n' > "$root/target.conf"
bash "$pid_undo" >/dev/null 2>&1 || rc=1
bash "$pid_undo" >/dev/null 2>&1 || rc=1
[ "$(cat "$root/target.conf")" = v1 ] || rc=1
if find "$root" -name '.*.stackalign-*' -print -quit | grep -q .; then rc=1; fi
[ "$rc" -eq 0 ] && ok "undo stage/backup names are PID-scoped" || bad "undo stage/backup names are PID-scoped"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
