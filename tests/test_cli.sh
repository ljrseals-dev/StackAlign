#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/bin/stackalign"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export SA_HISTORY_ROOT="$T/hist" SA_SECRETS_DIR="$T/secrets"
mkdir -p "$T/bin"; export FAKE_RPM_INSTALLED=""
cat > "$T/bin/rpm" <<'EOF'
#!/usr/bin/env bash
# fake: succeeds only for names listed in FAKE_RPM_INSTALLED
[ "$1" = -q ] || exit 1
for n in $FAKE_RPM_INSTALLED; do [ "$n" = "$2" ] && exit 0; done; exit 1
EOF
chmod +x "$T/bin/rpm"; export PATH="$T/bin:$PATH"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }
run() { OUT=$("$CLI" "$@" 2>&1); RC=$?; }

run version;            { [ $RC -eq 0 ] && [[ $OUT == "stackalign "* ]]; } && ok "version" || bad "version"
run --plan --version;   { [ $RC -eq 0 ] && [[ $OUT == "stackalign "* ]]; } && ok "--version ignores --plan" || bad "--version ignores --plan"
run help;               { [ $RC -eq 0 ] && [[ $OUT == *"commands:"* ]] && [[ $OUT == *rollback* ]] && [[ $OUT == *repo* ]]; } && ok "help lists commands" || bad "help lists commands"
run help doctor;        { [ $RC -eq 0 ] && [[ $OUT == *"read-only"* ]]; } && ok "help <cmd>" || bad "help <cmd>"
run help bogus;         [ $RC -eq 64 ] && ok "help unknown cmd -> 64" || bad "help unknown cmd -> 64"
run bogus;              [ $RC -eq 64 ] && ok "unknown command -> 64" || bad "unknown command -> 64"
run;                    [ $RC -eq 64 ] && ok "no command -> 64" || bad "no command -> 64"

# unexpected trailing options are errors, not silent drops
run version --plan;     { [ $RC -eq 64 ] && [[ $OUT == *"unexpected argument: --plan"* ]]; } && ok "trailing --plan on version -> error" || bad "trailing --plan on version -> error"
run doctor --yes;       { [ $RC -eq 64 ] && [[ $OUT == *"unexpected argument: --yes"* ]]; } && ok "trailing --yes -> error" || bad "trailing --yes -> error"
run doctor --apply;     [ $RC -eq 64 ] && ok "doctor refuses --apply (read-only)" || bad "doctor refuses --apply"
run install --frobnicate; [ $RC -eq 64 ] && ok "unknown trailing option -> error" || bad "unknown trailing option -> error"
run --frobnicate version; [ $RC -eq 64 ] && ok "unknown global flag -> error" || bad "unknown global flag -> error"
run install --plan --apply; [ $RC -eq 64 ] && ok "--plan with --apply rejected" || bad "--plan with --apply rejected"

# stubs refuse honestly
run install --plan;     { [ $RC -eq 2 ] && [[ $OUT == *"not implemented"*M2a* ]]; } && ok "stub install: rc 2, names milestone" || bad "stub install: rc 2, names milestone"
run plan tune;          { [ $RC -eq 2 ] && [[ $OUT == *"not implemented"* ]]; } && ok "plan <cmd> alias reaches command" || bad "plan <cmd> alias reaches command"
run plan;               [ $RC -eq 64 ] && ok "plan without command -> 64" || bad "plan without command -> 64"
run --yes --config "$T/x.conf" site list; [ $RC -eq 2 ] && ok "global flags before command accepted" || bad "global flags before command accepted"

# repo inventory is read-only and available from the CLI.
export SA_YUM_REPOS_DIR="$T/repos"
mkdir -p "$SA_YUM_REPOS_DIR"
cat > "$SA_YUM_REPOS_DIR/cli.repo" <<'EOF'
[cli-test]
baseurl=https://operator:do-not-print@example.invalid/repo
enabled=1
gpgcheck=1
gpgkey=https://example.invalid/key
EOF
run repo inventory
{
  [ "$RC" -eq 0 ] &&
  printf '%s\n' "$OUT" | awk -F '\t' '$1=="cli-test" && $2=="1" && $3=="1" && $4=="unset" && $5=="unset" && $6=="yes" && $9=="yes"' &&
  [[ "$OUT" != *"do-not-print"* ]]
} && ok "repo inventory CLI reports trust flags without credential leakage" || bad "repo inventory CLI/redaction"
run repo install
[ "$RC" -eq 64 ] && ok "repo inventory rejects unsupported mutating subcommands" || bad "repo inventory rejects unsupported subcommands"

# doctor
run --config "$T/none.conf" doctor
{ [ $RC -eq 0 ] && [[ $OUT == *"no critical findings"* ]]; } && ok "doctor clean host: rc 0" || bad "doctor clean host: rc 0 (rc=$RC)"
FAKE_RPM_INSTALLED="vsftpd" run doctor
{ [ $RC -eq 1 ] && [[ $OUT == *"CRITICAL: FTP daemon installed: vsftpd"* ]]; } && ok "doctor: FTP daemon is critical, rc 1" || bad "doctor: FTP daemon is critical"
# SA_CONF_PATH is internal; test config check via --config
printf '[meta]\nconfig_version = 1\n' > "$T/ok.conf"; printf '[meta]\nconfig_version = 9\n' > "$T/badver.conf"
run --config "$T/ok.conf" doctor;     { [ $RC -eq 0 ] && [[ $OUT == *"config: ok"* ]]; } && ok "doctor validates good config" || bad "doctor validates good config"
run --config "$T/badver.conf" doctor; { [ $RC -eq 1 ] && [[ $OUT == *"config: ERROR"* ]]; } && ok "doctor flags bad config version" || bad "doctor flags bad config version"

# rollback wired to history: plan does nothing, --apply restores
source "$ROOT/lib/history.sh"
printf 'v1\n' > "$T/f.conf"; id=$(sa_history_snapshot "$T/f.conf" cli); printf 'v2\n' > "$T/f.conf"
run rollback --list;  [[ $OUT == *"$id"* ]] && ok "rollback --list shows snapshot" || bad "rollback --list shows snapshot"
run rollback --to "$id"
{ [ $RC -eq 0 ] && [ "$(cat "$T/f.conf")" = v2 ] && [[ $OUT == *"plan:"* ]]; } && ok "rollback without --apply only plans" || bad "rollback without --apply only plans"
run --plan rollback --to "$id" --apply
{ [ $RC -eq 64 ] && [ "$(cat "$T/f.conf")" = v2 ]; } && ok "global --plan + trailing --apply rejected, nothing restored" || bad "global --plan + trailing --apply rejected, nothing restored"
run rollback --to "$id" --apply
{ [ $RC -eq 0 ] && [ "$(cat "$T/f.conf")" = v1 ]; } && ok "rollback --apply restores bytes" || bad "rollback --apply restores bytes"
run rollback --to nosuch --apply; [ $RC -eq 1 ] && ok "rollback unknown id -> rc 1" || bad "rollback unknown id -> rc 1"
run rollback; [ $RC -eq 64 ] && ok "rollback needs --list or --to" || bad "rollback needs --list or --to"

# secret: wired to lib/secret.sh (machine mode default); plan by default, --apply writes
export SA_SECRETS_DIR="$T/secrets"
run --config "$T/none.conf" secret gen dbroot
{ [ $RC -eq 0 ] && [[ $OUT == *"plan:"* ]] && [ ! -e "$T/secrets" ]; } && ok "secret gen without --apply only plans" || bad "secret gen without --apply only plans"
OUT=$("$CLI" --config "$T/none.conf" secret gen dbroot --apply 2>/dev/null); RC=$?
{ [ $RC -eq 0 ] && [ ${#OUT} -eq 44 ] && [ -f "$T/secrets/dbroot.hash" ]; } && ok "secret gen --apply: value on stdout, hash stored" || bad "secret gen --apply (rc=$RC)"
run secret list; [ "$OUT" = dbroot ] && ok "secret list shows names only" || bad "secret list shows names only ('$OUT')"
run secret gen dbroot --apply; [ $RC -eq 3 ] && ok "secret gen existing name -> rc 3" || bad "secret gen existing name (rc=$RC)"
run secret; [ $RC -eq 64 ] && ok "secret without subcommand -> 64" || bad "secret without subcommand"
run secret gen; [ $RC -eq 64 ] && ok "secret gen without name -> 64" || bad "secret gen without name"
run secret list --yes; [ $RC -eq 64 ] && ok "secret list rejects unexpected option" || bad "secret list rejects unexpected option"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
