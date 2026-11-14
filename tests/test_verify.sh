#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_verify.sh -- release verification with REAL gpg/gpgv and throwaway keys.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v gpg >/dev/null 2>&1 || ! command -v gpgv >/dev/null 2>&1; then
    echo "NOT RUN: gpg/gpgv not installed (install gnupg2 to run this suite)"; exit 0
fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GNUPGHOME="$T/gpg"; mkdir -m 700 "$GNUPGHOME"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2' want '$3')"; fail=1; fi; }

genkey() { gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-generate-key "$1" ed25519 sign never 2>/dev/null; }
fprof() { gpg --list-keys --with-colons "$1" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}'; }
genkey "StackAlign Test <rel@test.invalid>"; genkey "Attacker <evil@test.invalid>"
FPR="$(fprof rel@test.invalid)"; EVIL="$(fprof evil@test.invalid)"
gpg --export rel@test.invalid > "$T/ring-good.gpg" 2>/dev/null
cat "$T/ring-good.gpg" > "$T/ring-both.gpg"; gpg --export evil@test.invalid >> "$T/ring-both.gpg" 2>/dev/null
[ -n "$FPR" ] && [ -n "$EVIL" ] && [ "$FPR" != "$EVIL" ]; check "throwaway keys created" "$?" 0

NAME="stackalign-0.1.0.tar.gz"
# mkrel <dir> <expires-line-or-empty> <signer-fingerprint>
mkrel() {
    local d=$1 exp=$2 who=$3
    rm -rf "$d"; mkdir -p "$d"
    printf 'release payload\n' > "$d/$NAME"
    { [ -n "$exp" ] && echo "# expires: $exp"; echo "$(sha256sum "$d/$NAME" | awk '{print $1}')  $NAME"; } > "$d/SHA256SUMS"
    gpg --batch --yes --quiet --pinentry-mode loopback --passphrase '' --local-user "$who" \
        --detach-sign --output "$d/SHA256SUMS.sig" "$d/SHA256SUMS" 2>/dev/null
}
verify() { # dir ring fpr
    ( . "$ROOT/lib/verify.sh"; sa_verify_artifact "$1/$NAME" "$1/SHA256SUMS" "$1/SHA256SUMS.sig" "$2" "$3" ) >"$T/out" 2>"$T/err"
}
FUT="2099-01-01T00:00:00Z"; PAST="2000-01-01T00:00:00Z"

mkrel "$T/r1" "$FUT" "$FPR"; verify "$T/r1" "$T/ring-good.gpg" "$FPR"; check "valid release => 0" "$?" 0
check "prints the verified path" "$(cat "$T/out")" "$T/r1/$NAME"
verify "$T/r1" "$T/ring-good.gpg" "$(echo "$FPR" | tr 'A-F' 'a-f')"; check "lowercase pin accepted" "$?" 0

mkrel "$T/r2" "$FUT" "$FPR"; echo tamper >> "$T/r2/$NAME"
verify "$T/r2" "$T/ring-good.gpg" "$FPR"; check "tampered artifact => 5" "$?" 5

mkrel "$T/r3" "$FUT" "$FPR"; echo "# extra line" >> "$T/r3/SHA256SUMS"
verify "$T/r3" "$T/ring-good.gpg" "$FPR"; check "tampered SHA256SUMS (bad signature) => 4" "$?" 4

mkrel "$T/r4" "$FUT" "$EVIL"
verify "$T/r4" "$T/ring-good.gpg" "$FPR"; check "attacker-signed, key not in keyring => 4" "$?" 4
verify "$T/r4" "$T/ring-both.gpg" "$FPR"; check "attacker key in keyring but not pinned => 4" "$?" 4
mkrel "$T/r5" "$FUT" "$FPR"
verify "$T/r5" "$T/ring-both.gpg" "$EVIL"; check "wrong pinned fingerprint => 4" "$?" 4
verify "$T/r5" "$T/ring-good.gpg" "NOTAFINGERPRINT"; check "malformed pin => 64" "$?" 64

mkrel "$T/r6" "$PAST" "$FPR"; verify "$T/r6" "$T/ring-good.gpg" "$FPR"; check "expired metadata => 6" "$?" 6
mkrel "$T/r7" "" "$FPR";      verify "$T/r7" "$T/ring-good.gpg" "$FPR"; check "no expiry line => 6" "$?" 6
mkrel "$T/r8" "garbage" "$FPR"; verify "$T/r8" "$T/ring-good.gpg" "$FPR"; check "malformed expiry => 6" "$?" 6
mkrel "$T/r8b" "2099-99-99T00:00:00Z" "$FPR"; verify "$T/r8b" "$T/ring-good.gpg" "$FPR"; check "invalid calendar date => 6" "$?" 6
mkrel "$T/r8c" "$FUT" "$FPR"; { echo "# expires: $FUT"; cat "$T/r8c/SHA256SUMS"; } > "$T/r8c/duplicate"
mv "$T/r8c/duplicate" "$T/r8c/SHA256SUMS"
gpg --batch --yes --quiet --pinentry-mode loopback --passphrase '' --local-user "$FPR" --detach-sign --output "$T/r8c/SHA256SUMS.sig" "$T/r8c/SHA256SUMS" 2>/dev/null
verify "$T/r8c" "$T/ring-good.gpg" "$FPR"; check "duplicate expiry declarations => 6" "$?" 6

mkrel "$T/r9" "$FUT" "$FPR"; { echo "# expires: $FUT"; echo "$(sha256sum "$T/r9/$NAME" | awk '{print $1}')  other.tar.gz"; } > "$T/r9/SHA256SUMS"
gpg --batch --yes --quiet --pinentry-mode loopback --passphrase '' --local-user "$FPR" --detach-sign --output "$T/r9/SHA256SUMS.sig" "$T/r9/SHA256SUMS" 2>/dev/null
verify "$T/r9" "$T/ring-good.gpg" "$FPR"; check "artifact not listed => 5" "$?" 5

mkrel "$T/r10" "$FUT" "$FPR"; H="$(sha256sum "$T/r10/$NAME" | awk '{print $1}')"
{ echo "# expires: $FUT"; echo "$H  $NAME"; echo "$H  $NAME"; } > "$T/r10/SHA256SUMS"
gpg --batch --yes --quiet --pinentry-mode loopback --passphrase '' --local-user "$FPR" --detach-sign --output "$T/r10/SHA256SUMS.sig" "$T/r10/SHA256SUMS" 2>/dev/null
verify "$T/r10" "$T/ring-good.gpg" "$FPR"; check "duplicate entries => 5" "$?" 5

mkrel "$T/r11" "$FUT" "$FPR"; : > "$T/r11/SHA256SUMS.sig"
verify "$T/r11" "$T/ring-good.gpg" "$FPR"; check "empty signature file => 4" "$?" 4
mkrel "$T/r12" "$FUT" "$FPR"; rm "$T/r12/SHA256SUMS.sig"
verify "$T/r12" "$T/ring-good.gpg" "$FPR"; check "missing signature file => 64" "$?" 64
mkrel "$T/r13" "$FUT" "$FPR"; mv "$T/r13/$NAME" "$T/r13/bad name.tgz"; NAME_SAVE=$NAME; NAME="bad name.tgz"
verify "$T/r13" "$T/ring-good.gpg" "$FPR"; check "unsafe artifact name => 64" "$?" 64; NAME=$NAME_SAVE

# --- fake gpgv: status-line handling (revoked/expired keys, duplicate or missing VALIDSIG) ---
mkdir -p "$T/fake"; mkrel "$T/r14" "$FUT" "$FPR"
fakegpgv() { printf '#!/usr/bin/env bash\ncat <<STATUS\n%s\nSTATUS\nexit 0\n' "$1" > "$T/fake/gpgv"; chmod +x "$T/fake/gpgv"; }
V="[GNUPG:] VALIDSIG $FPR 2026-01-01 1 0 4 0 22 10 00 $FPR"
G="[GNUPG:] GOODSIG ABCD StackAlign Test"
fakegpgv "$G
$V"; ( PATH="$T/fake:$PATH"; verify "$T/r14" "$T/ring-good.gpg" "$FPR" ); check "fake gpgv: good status => 0" "$?" 0
fakegpgv "[GNUPG:] REVKEYSIG ABCD x
$G
$V"; ( PATH="$T/fake:$PATH"; verify "$T/r14" "$T/ring-good.gpg" "$FPR" ); check "revoked key => 4" "$?" 4
fakegpgv "[GNUPG:] EXPKEYSIG ABCD x
$G
$V"; ( PATH="$T/fake:$PATH"; verify "$T/r14" "$T/ring-good.gpg" "$FPR" ); check "expired key => 4" "$?" 4
fakegpgv "$G"; ( PATH="$T/fake:$PATH"; verify "$T/r14" "$T/ring-good.gpg" "$FPR" ); check "GOODSIG without VALIDSIG => 4" "$?" 4
fakegpgv "$G
$V
$V"; ( PATH="$T/fake:$PATH"; verify "$T/r14" "$T/ring-good.gpg" "$FPR" ); check "two VALIDSIG lines => 4" "$?" 4
fakegpgv "$G
[GNUPG:] VALIDSIG $EVIL 2026-01-01 1 0 4 0 22 10 00 $FPR"; ( PATH="$T/fake:$PATH"; verify "$T/r14" "$T/ring-good.gpg" "$FPR" ); check "signing subkey is fine when PRIMARY matches pin" "$?" 0
fakegpgv "$G
[GNUPG:] VALIDSIG $FPR 2026-01-01 1 0 4 0 22 10 00 $EVIL"; ( PATH="$T/fake:$PATH"; verify "$T/r14" "$T/ring-good.gpg" "$FPR" ); check "primary fingerprint differs from pin => 4" "$?" 4

# --- anti-downgrade ---
( . "$ROOT/lib/verify.sh"
  sa_verify_not_downgrade 1.2.0 1.3.0 2>/dev/null; echo "up $?"
  sa_verify_not_downgrade 1.2.0 1.2.0 2>/dev/null; echo "same $?"
  sa_verify_not_downgrade 1.10.0 1.9.0 2>/dev/null; echo "down $?"
  SA_ALLOW_DOWNGRADE=1 sa_verify_not_downgrade 1.10.0 1.9.0 2>/dev/null; echo "env_override $?"
  sa_verify_not_downgrade 1.2.0 1.2.0-rc1 2>/dev/null; echo "badver $?" ) > "$T/dg"
check "upgrade ok" "$(grep '^up ' "$T/dg")" "up 0"
check "same version ok" "$(grep '^same ' "$T/dg")" "same 0"
check "downgrade refused (1.10 -> 1.9, numeric not lexical)" "$(grep '^down ' "$T/dg")" "down 7"
check "environment override cannot authorize rollback" "$(grep '^env_override ' "$T/dg")" "env_override 7"
check "pre-release tags rejected" "$(grep '^badver ' "$T/dg")" "badver 64"
exit "$fail"
