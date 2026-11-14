#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Real OpenSSH integration test for generated SFTP Match policy and chroot behavior.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || { echo "SKIP: real sshd test requires root"; exit 0; }
  exec sudo -E bash "$0"
fi

command -v sshd >/dev/null 2>&1 || { echo "SKIP: OpenSSH server is not installed"; exit 0; }
command -v sftp >/dev/null 2>&1 || { echo "SKIP: OpenSSH client is not installed"; exit 0; }
SSHD_BIN="$(readlink -f "$(command -v sshd)")"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d /var/lib/stackalign-sftp-test.XXXXXX)"
GROUP="saftp$(printf '%x' "$$" | tail -c 5)"
SFTP_USER="sftp$(printf '%x' "$$" | tail -c 5)"
SSH_USER="ssh$(printf '%x' "$$" | tail -c 6)"
PORT=$((22000 + ($$ % 20000)))
SSHD_PID=""

cleanup() {
  if [ -n "$SSHD_PID" ]; then kill "$SSHD_PID" 2>/dev/null || true; wait "$SSHD_PID" 2>/dev/null || true; fi
  userdel "$SFTP_USER" 2>/dev/null || true
  userdel "$SSH_USER" 2>/dev/null || true
  groupdel "$GROUP" 2>/dev/null || true
  rm -rf -- "$T"
}
trap cleanup EXIT

mkdir -p "$T/sshd_config.d" "$T/keys" "$T/sftp" /run/sshd
chmod 0755 "$T"
export SA_SFTP_GROUP="$GROUP"
export SA_SFTP_BASE="$T/sftp"
export SA_SFTP_KEYDIR="$T/keys"
export SA_SFTP_DROPIN="$T/sshd_config.d/50-stackalign-sftp.conf"

ssh-keygen -q -t ed25519 -N '' -f "$T/sftp_client"
ssh-keygen -q -t ed25519 -N '' -f "$T/ordinary_client"
ssh-keygen -q -t ed25519 -N '' -f "$T/host_key"

. "$ROOT/lib/sftp.sh"
sa_sftp_add_user "$SFTP_USER" "$T/sftp_client.pub"
useradd -m -s /bin/sh "$SSH_USER"
install -d -m 0700 -o "$SSH_USER" -g "$SSH_USER" "/home/$SSH_USER/.ssh"
install -m 0600 -o "$SSH_USER" -g "$SSH_USER" "$T/ordinary_client.pub" "/home/$SSH_USER/.ssh/authorized_keys"

sa_sftp_render > "$SA_SFTP_DROPIN"
cat > "$T/sshd_config" <<EOF
Port $PORT
ListenAddress 127.0.0.1
HostKey $T/host_key
PidFile $T/sshd.pid
AuthorizedKeysFile .ssh/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin no
StrictModes yes
UsePAM no
UseDNS no
AllowTcpForwarding yes
AllowAgentForwarding yes
X11Forwarding yes
PermitTTY yes
Subsystem sftp internal-sftp
Include $SA_SFTP_DROPIN
EOF

if ! sshd -t -f "$T/sshd_config"; then
  echo "FAIL: sshd -t rejected generated configuration" >&2
  cat "$T/sshd_config" >&2
  exit 1
fi
echo "PASS: sshd -t"
SFTP_EFFECTIVE="$(sshd -T -f "$T/sshd_config" -C "user=$SFTP_USER,host=localhost,addr=127.0.0.1")"
SSH_EFFECTIVE="$(sshd -T -f "$T/sshd_config" -C "user=$SSH_USER,host=localhost,addr=127.0.0.1")"
grep -Fq 'forcecommand internal-sftp -d /files' <<<"$SFTP_EFFECTIVE" || { echo "FAIL: SFTP ForceCommand missing" >&2; printf '%s\n' "$SFTP_EFFECTIVE" >&2; exit 1; }
grep -Fq 'passwordauthentication no' <<<"$SFTP_EFFECTIVE"
grep -Fq 'permittty no' <<<"$SFTP_EFFECTIVE"
grep -Fq 'allowtcpforwarding no' <<<"$SFTP_EFFECTIVE"
grep -Fq 'x11forwarding no' <<<"$SFTP_EFFECTIVE"
grep -Fq "chrootdirectory $SA_SFTP_BASE/%u" <<<"$SFTP_EFFECTIVE" || { echo "FAIL: SFTP ChrootDirectory missing" >&2; printf '%s\n' "$SFTP_EFFECTIVE" >&2; exit 1; }
grep -Fq 'forcecommand none' <<<"$SSH_EFFECTIVE" || { echo "FAIL: ordinary SSH ForceCommand changed" >&2; printf '%s\n' "$SSH_EFFECTIVE" >&2; exit 1; }
grep -Fq 'permittty yes' <<<"$SSH_EFFECTIVE"
grep -Fq 'allowtcpforwarding yes' <<<"$SSH_EFFECTIVE"
grep -Fq 'chrootdirectory none' <<<"$SSH_EFFECTIVE"

"$SSHD_BIN" -D -f "$T/sshd_config" -E "$T/sshd.log" &
SSHD_PID=$!
for _ in $(seq 1 50); do
  if ssh -p "$PORT" -i "$T/ordinary_client" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=1 "$SSH_USER@127.0.0.1" true >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

printf 'sftp-chroot-proof\n' > "$T/payload"
printf 'pwd\nput %s payload\nquit\n' "$T/payload" | timeout 20s sftp -b - -P "$PORT" -i "$T/sftp_client" \
  -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$SFTP_USER@127.0.0.1" > "$T/sftp.out"
grep -Fq '/files' "$T/sftp.out"
cmp "$T/payload" "$SA_SFTP_BASE/$SFTP_USER/files/payload"

ORDINARY_OUT="$(timeout 15s ssh -p "$PORT" -i "$T/ordinary_client" -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@127.0.0.1" 'printf ordinary-login-ok')"
[ "$ORDINARY_OUT" = ordinary-login-ok ]

echo "test_sftp_openssh: real sshd config, effective Match policy, chrooted SFTP transfer, and ordinary SSH login passed"
