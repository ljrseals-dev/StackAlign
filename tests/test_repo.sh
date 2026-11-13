#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Fake dnf/rpm/curl/gpg in a private PATH. No real package manager is touched.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export SA_YUM_REPOS_DIR="$T/yum.repos.d" FAKE_LOG="$T/calls.log" FAKE_STATE="$T/state"
mkdir -p "$T/bin" "$FAKE_STATE"
FPR=0123456789ABCDEF0123456789ABCDEF01234567
export FAKE_FPR=$FPR FAKE_MULTI=0

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$FAKE_LOG"
out=""
while [ $# -gt 0 ]; do
  case $1 in
    --output|-o) out=$2; shift 2 ;;
    --) shift; break ;;
    *) shift ;;
  esac
done
[ -e "$FAKE_STATE/curl_fail" ] && exit 22
echo "KEYDATA" > "$out"
EOF
cat > "$T/bin/gpg" <<'EOF'
#!/usr/bin/env bash
echo "pub:-:2048:1:FAKEPRIMARY:::::::::"
echo "fpr:::::::::${FAKE_FPR}:"
echo "uid:-:::::::Test Key:"
echo "sub:-:2048:1:FAKESUBKEY:::::::::"
echo "fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:"
if [ "${FAKE_MULTI:-0}" = 1 ]; then
  echo "pub:-:2048:1:ATTACKERKEY:::::::::"
  echo "fpr:::::::::BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB:"
fi
EOF
cat > "$T/bin/rpm" <<'EOF'
#!/usr/bin/env bash
echo "rpm $*" >> "$FAKE_LOG"
case $1 in
  --import) exit 0 ;;
  -q) [ -e "$FAKE_STATE/installed.$2" ] ;;
esac
EOF
cat > "$T/bin/dnf" <<'EOF'
#!/usr/bin/env bash
echo "dnf $*" >> "$FAKE_LOG"
if [ "$1" = install ]; then touch "$FAKE_STATE/installed.${@: -1}"; fi
exit 0
EOF
chmod +x "$T/bin"/*; export PATH="$T/bin:$PATH"
source "$ROOT/lib/repo.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }
reset() {
  : > "$FAKE_LOG"
  : "${FAKE_STATE:?}" "${SA_YUM_REPOS_DIR:?}"
  [[ "$FAKE_STATE" != / && "$SA_YUM_REPOS_DIR" != / ]] || return 1
  find "$FAKE_STATE" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  rm -rf -- "$SA_YUM_REPOS_DIR"
}
URL=https://example.invalid/el9/x86_64/; KEY=https://example.invalid/RPM-GPG-KEY

# setup writes repo file + imports key
reset; sa_repo_setup remi "$URL" "$FPR" "$KEY" >/dev/null; rc=$?
f="$SA_YUM_REPOS_DIR/stackalign-remi.repo"
{ [ $rc -eq 0 ] && grep -q "baseurl=$URL" "$f" && grep -q 'gpgcheck=1' "$f" && grep -q 'rpm --import' "$FAKE_LOG"; } \
  && ok "setup writes repo file (gpgcheck=1) and imports key" || bad "setup writes repo file and imports key"
[ "$(stat -c %a "$f")" = 644 ] && ok "repo file mode 0644" || bad "repo file mode 0644"

# idempotent
m1=$(stat -c %y "$f"); sleep 1.1; out=$(sa_repo_setup remi "$URL" "$FPR" "$KEY")
{ [ "$out" = "repo remi: unchanged" ] && [ "$m1" = "$(stat -c %y "$f")" ]; } && ok "setup idempotent (file untouched)" || bad "setup idempotent"

# fingerprint with spaces + lowercase accepted
reset; sa_repo_setup remi "$URL" "0123 4567 89ab cdef 0123 4567 89ab cdef 0123 4567" "$KEY" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && ok "fingerprint spaces/case normalised" || bad "fingerprint spaces/case normalised (rc=$rc)"

# fingerprint mismatch: refused, nothing written, nothing imported
reset; FAKE_FPR=FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF sa_repo_setup remi "$URL" "$FPR" "$KEY" 2>/dev/null; rc=$?
{ [ $rc -eq 4 ] && [ ! -e "$f" ] && ! grep -q 'rpm --import' "$FAKE_LOG"; } && ok "fingerprint mismatch: rc 4, no file, no import" || bad "fingerprint mismatch: rc 4, no file, no import (rc=$rc)"

# Multiple primary keys: reject before repo write or rpm import.
reset; FAKE_MULTI=1 sa_repo_setup remi "$URL" "$FPR" "$KEY" 2>/dev/null; rc=$?; FAKE_MULTI=0
{ [ $rc -eq 4 ] && [ ! -e "$f" ] && ! grep -q 'rpm --import' "$FAKE_LOG"; } \
  && ok "multi-key bundle refused: rc 4, no repo file, no import" || bad "multi-key bundle refused (rc=$rc)"

# Primary fingerprint is selected, not a later subkey fingerprint.
reset; sa_repo_setup remi "$URL" "$FPR" "$KEY" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && ok "primary fingerprint accepted despite subkey fingerprint" || bad "primary fingerprint selection (rc=$rc)"

# key download failure
reset; touch "$FAKE_STATE/curl_fail"; sa_repo_setup remi "$URL" "$FPR" "$KEY" 2>/dev/null; rc=$?
{ [ $rc -ne 0 ] && [ ! -e "$f" ]; } && ok "key download failure: nothing written" || bad "key download failure: nothing written"

# argument validation (data, not code)
reset
sa_repo_setup 'x;rm -rf /' "$URL" "$FPR" "$KEY" 2>/dev/null; r1=$?
sa_repo_setup remi "http://insecure/" "$FPR" "$KEY" 2>/dev/null; r2=$?
sa_repo_setup remi "$URL" "NOTHEX" "$KEY" 2>/dev/null; r3=$?
sa_repo_setup remi "$URL"$'\n[evil]' "$FPR" "$KEY" 2>/dev/null; r4=$?
{ [ $r1 -eq 64 ] && [ $r2 -eq 64 ] && [ $r3 -eq 64 ] && [ $r4 -eq 64 ] && [ ! -s "$FAKE_LOG" ]; } \
  && ok "bad name / http url / bad fpr / newline injection all rejected (64), no commands run" || bad "argument validation ($r1 $r2 $r3 $r4)"

# FTP daemons refused
reset
for p in vsftpd pure-ftpd proftpd ProFTPD vsftpd-3.0.5; do
  m=$(sa_repo_install remi "$p" 1.0 "$URL" "$FPR" "$KEY" 2>&1 >/dev/null); rc=$?
  { [ $rc -eq 3 ] && [[ $m == *error=ftp_daemon_refused* ]]; } || { bad "ftp refused: $p"; continue; }
done
{ ! grep -q '^dnf' "$FAKE_LOG" && [ ! -e "$f" ]; } && ok "FTP daemons refused (error=ftp_daemon_refused); no dnf, no repo setup" || bad "FTP refusal side effects"
sa_repo_versionlock remi vsftpd 1.0 2>/dev/null; [ $? -eq 3 ] && ok "versionlock also refuses FTP" || bad "versionlock also refuses FTP"

# install: setup + install + versionlock + health, idempotent second run
reset; sa_repo_install remi nginx 1.2.3 "$URL" "$FPR" "$KEY" >/dev/null; rc=$?
{ [ $rc -eq 0 ] && grep -q 'dnf install -y -- nginx-1.2.3' "$FAKE_LOG" && grep -q 'dnf versionlock add -- nginx-1.2.3' "$FAKE_LOG"; } \
  && ok "install: setup, dnf install, versionlock, health check" || bad "install flow (rc=$rc)"
: > "$FAKE_LOG"; sa_repo_install remi nginx 1.2.3 >/dev/null; rc=$?
{ [ $rc -eq 0 ] && ! grep -q 'dnf install' "$FAKE_LOG"; } && ok "install idempotent: no reinstall when present" || bad "install idempotent"

# install without prior setup and without repo args refuses
reset; sa_repo_install remi nginx 1.2.3 2>/dev/null; rc=$?
{ [ $rc -ne 0 ] && ! grep -q '^dnf' "$FAKE_LOG"; } && ok "install without repo setup refuses" || bad "install without repo setup refuses"

# Read-only inventory reports per-repo trust settings without leaking URLs or credentials.
reset
mkdir -p "$SA_YUM_REPOS_DIR"
cat > "$SA_YUM_REPOS_DIR/inventory.repo" <<'EOF'
[trusted-third-party]
name=Trusted test repository
baseurl=https://user:secret@example.invalid/path?token=hidden
enabled=1
gpgcheck=1
repo_gpgcheck=0
sslverify=1
gpgkey=https://example.invalid/RPM-GPG-KEY

[disabled-mirror]
name=Disabled mirror
mirrorlist=https://user:secret@example.invalid/mirrorlist
enabled=0
gpgcheck=0
EOF
inventory=$(sa_repo_inventory); rc=$?
{
  [ "$rc" -eq 0 ] &&
  printf '%s\n' "$inventory" | awk -F '\t' '$1=="trusted-third-party" && $2=="1" && $3=="1" && $4=="0" && $5=="1" && $6=="yes" && $9=="yes"' &&
  printf '%s\n' "$inventory" | awk -F '\t' '$1=="disabled-mirror" && $2=="0" && $3=="0" && $4=="unset" && $5=="unset" && $6=="no" && $7=="yes"' &&
  [[ "$inventory" != *"secret"* ]] &&
  [[ "$inventory" != *"token=hidden"* ]]
} && ok "inventory reports repo policy flags and redacts credential-bearing values" || bad "repository inventory output/redaction"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
