#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_sftp.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/sshd_config.d"; : > "$T/calls"; : > "$T/users"
export CALLS="$T/calls" USERS="$T/users" GROUPF="$T/group" PATH="$T/bin:$PATH"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2' want '$3')"; fail=1; fi; }
mkfake() { printf "%s\n" "#!/usr/bin/env bash" "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }

mkfake id 'u="${@: -1}"; l="$(grep -E "^$u(:|$)" "$USERS" | head -1)"; [ -n "$l" ] || exit 1; if [ "$1" = -nG ]; then echo -n "$u wheel"; case "$l" in *:sftp) echo -n " sftponly" ;; esac; echo; fi'
mkfake getent 'if [ "$1" = group ]; then [ -f "$GROUPF" ] || exit 2; echo "sftponly:x:1001:alice,carol"; fi'
mkfake groupadd 'echo "groupadd $*" >> "$CALLS"; touch "$GROUPF"'
mkfake useradd 'echo "useradd $*" >> "$CALLS"; echo "${@: -1}:sftp" >> "$USERS"'
mkfake userdel 'echo "userdel $*" >> "$CALLS"; grep -v "^${@: -1}:" "$USERS" > "$USERS.n"; mv "$USERS.n" "$USERS"'
mkfake install 'echo "install $*" >> "$CALLS"; for a in "$@"; do :; done; for a in "$@"; do case "$a" in -*|root|sftponly) ;; *) [ "$a" = "--" ] || mkdir -p "$a" ;; esac; done'
mkfake chown 'echo "chown $*" >> "$CALLS"'
mkfake sshd 'echo "sshd $*" >> "$CALLS"; exit "${FAKE_SSHD_RC:-0}"'
mkfake systemctl 'echo "systemctl $*" >> "$CALLS"; [ "$1" = reload ] && exit "${FAKE_RELOAD_RC:-0}"; exit 0'

export SA_SFTP_BASE="$T/sftp" SA_SFTP_KEYDIR="$T/keys" SA_SFTP_DROPIN="$T/sshd_config.d/50-stackalign-sftp.conf"
. "$ROOT/lib/sftp.sh"

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyData0123456789abcdefghijk user@host'
printf '%s\n' "$KEY" > "$T/good.pub"
printf '%s\n' 'command="rm -rf /" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA x' > "$T/opts.pub"
printf '%s\n%s\n' "$KEY" "$KEY" > "$T/two.pub"
printf '%s\n' 'ssh-dss AAAAB3NzaC1kc3MAAACB x' > "$T/dss.pub"

for bad in "root" "Alice" "a b" "../x" "a;b" "" "-rf"; do
  sa_sftp_add_user "$bad" "$T/good.pub" >/dev/null 2>&1; check "bad user '$bad'" "$?" 64
done
for kf in opts two dss; do
  sa_sftp_add_user eve "$T/$kf.pub" >/dev/null 2>&1; check "bad key ($kf)" "$?" 64
done
sa_sftp_add_user eve "$T/missing.pub" >/dev/null 2>&1; check "missing key file" "$?" 64
grep -q useradd "$CALLS"; check "no useradd on bad input" "$?" 1

sa_sftp_add_user alice "$T/good.pub" >/dev/null 2>&1; check "add alice ok" "$?" 0
grep -q "groupadd -- sftponly" "$CALLS"; check "group created when missing" "$?" 0
grep -q "useradd -g sftponly -M -d $T/sftp/alice -s /sbin/nologin -- alice" "$CALLS"; check "useradd flags (nologin, no home skeleton)" "$?" 0
grep -q "install -d -m 0755 -o root -g root -- $T/sftp $T/keys $T/sftp/alice" "$CALLS"; check "chroot root-owned 0755" "$?" 0
grep -q "install -d -m 0700 -o alice -g sftponly -- $T/sftp/alice/files" "$CALLS"; check "upload dir owned by user 0700" "$?" 0
check "key file content" "$(cat "$T/keys/alice")" "$KEY"
check "key file mode 644" "$(stat -c %a "$T/keys/alice")" 644
grep -q "chown root:root" "$CALLS"; check "key file root-owned" "$?" 0

: > "$CALLS"; sa_sftp_add_user alice "$T/good.pub" >/dev/null 2>&1; check "re-add rotates key" "$?" 0
grep -q "useradd" "$CALLS"; check "no second useradd" "$?" 1
grep -q "groupadd" "$CALLS"; check "group not recreated" "$?" 1

echo "bob" >> "$USERS"
: > "$CALLS"; sa_sftp_add_user bob "$T/good.pub" >/dev/null 2>&1; check "existing normal account refused" "$?" 1
[ -e "$T/keys/bob" ]; check "no key written for refused account" "$?" 1

sa_sftp_remove_user bob >/dev/null 2>&1; check "remove non-SFTP account refused" "$?" 1
grep -q userdel "$CALLS"; check "no userdel for bob" "$?" 1
sa_sftp_remove_user alice >/dev/null 2>&1; check "remove sftp user ok" "$?" 0
grep -q "userdel -- alice" "$CALLS" && ! grep -q -- "userdel -r" "$CALLS"; check "userdel without -r" "$?" 0
[ -e "$T/keys/alice" ]; check "key removed" "$?" 1
[ -d "$T/sftp/alice/files" ]; check "data kept" "$?" 0

r="$(sa_sftp_render)"
for want in "Match Group sftponly" "ChrootDirectory $T/sftp/%u" "ForceCommand internal-sftp -d /files" "AuthorizedKeysFile $T/keys/%u" "PasswordAuthentication no" "PermitTTY no" "AllowTcpForwarding no"; do
  case "$r" in *"$want"*) check "render has: $want" 0 0 ;; *) check "render has: $want" 1 0 ;; esac
done

: > "$CALLS"; sa_sftp_enable >/dev/null 2>&1; check "enable ok" "$?" 0
grep -q "Match Group sftponly" "$SA_SFTP_DROPIN"; check "drop-in installed" "$?" 0
grep -q "^sshd -t" "$CALLS"; check "sshd -t ran" "$?" 0
grep -q "systemctl reload sshd" "$CALLS"; check "sshd reloaded" "$?" 0
leftovers=0
for f in "$T/sshd_config.d"/.sa-sftp*; do
  [ -e "$f" ] || continue
  leftovers=$((leftovers + 1))
done
check "no temp files left" "$leftovers" 0

printf 'OLD\n' > "$SA_SFTP_DROPIN"; : > "$CALLS"
FAKE_SSHD_RC=1 sa_sftp_enable >/dev/null 2>&1; check "sshd -t failure => rc 1" "$?" 1
check "previous drop-in restored" "$(cat "$SA_SFTP_DROPIN")" OLD
grep -q "reload" "$CALLS"; check "no reload after failed check" "$?" 1

rm -f "$SA_SFTP_DROPIN"; FAKE_SSHD_RC=1 sa_sftp_enable >/dev/null 2>&1
[ -e "$SA_SFTP_DROPIN" ]; check "first-time failure removes drop-in" "$?" 1

printf 'OLD\n' > "$SA_SFTP_DROPIN"; FAKE_RELOAD_RC=1 sa_sftp_enable >/dev/null 2>&1; check "reload failure => rc 1" "$?" 1
check "reload failure restores previous" "$(cat "$SA_SFTP_DROPIN")" OLD

check "list members" "$(sa_sftp_list | tr '\n' ' ')" "alice carol "
exit "$fail"
