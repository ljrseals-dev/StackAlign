#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Fake curl (HIBP) and argon2 in a private PATH. No network. Real openssl/sha*sum.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
export SA_SECRETS_DIR="$T/secrets" FAKE_LOG="$T/calls.log" FAKE_HIBP_BODY="$T/hibp.body" FAKE_ARGV="$T/argv.log"

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$FAKE_LOG"
[ -e "$T_FAIL" ] && exit 22
url=""; for a in "$@"; do url=$a; done
if [[ $url == *range/5BAA6 ]]; then echo '1E4C9B93F3F0682250B6CF8331B7EE68FD8:3730471'; else cat "$FAKE_HIBP_BODY"; fi
EOF
cat > "$T/bin/argon2" <<'EOF'
#!/usr/bin/env bash
echo "argon2 $*" >> "$FAKE_ARGV"; cat >/dev/null
echo '$argon2id$v=19$m=16384,t=2,p=1$FAKESALT$FAKEHASH'
EOF
chmod +x "$T/bin"/*; export PATH="$T/bin:$PATH"
export T_FAIL="$T/curl_fail"
printf '00000000000000000000000000000000000:1\n' > "$FAKE_HIBP_BODY"
printf 'w%04d\n' $(seq 1 7776) > "$T/words.txt"; export SA_WORDLIST="$T/words.txt"

# shellcheck source=../lib/secret.sh
source "$ROOT/lib/secret.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }
reset() { rm -rf "$SA_SECRETS_DIR" "$T_FAIL"; : > "$FAKE_LOG"; : > "$FAKE_ARGV"; unset SA_MODE; }

# --- machine mode
reset; val=$(sa_secret_gen dbroot machine 2>/dev/null); rc=$?
f="$SA_SECRETS_DIR/dbroot.hash"
{ [ $rc -eq 0 ] && [ ${#val} -eq 44 ] && [[ $val == *= ]]; } && ok "machine: 44-char base64 (256-bit) value printed" || bad "machine value shape (rc=$rc len=${#val})"
want="sha256:$(printf '%s' "$val" | sha256sum | awk '{print $1}')"
[ "$(cat "$f")" = "$want" ] && ok "machine: stored hash is SHA-256 of the printed value" || bad "machine: stored hash is SHA-256 of value"
{ [ "$(stat -c %a "$f")" = 600 ] && [ "$(stat -c %a "$SA_SECRETS_DIR")" = 700 ]; } && ok "perms: file 0600, dir 0700" || bad "perms: file 0600, dir 0700"
grep -rqF -- "$val" "$SA_SECRETS_DIR" && bad "value NOT on disk" || ok "value never written to disk"
{ [ ! -s "$FAKE_LOG" ] && [ ! -s "$FAKE_ARGV" ]; } && ok "machine: no HIBP call, no argon2 (primitives not confused)" || bad "machine: no HIBP/argon2"
val2=$(sa_secret_gen dbroot2 machine 2>/dev/null); [ "$val" != "$val2" ] && ok "two machine secrets differ" || bad "two machine secrets differ"

# --- never overwrite
before=$(cat "$f"); sa_secret_gen dbroot machine >/dev/null 2>&1; rc=$?
{ [ $rc -eq 3 ] && [ "$(cat "$f")" = "$before" ]; } && ok "existing name refused (rc 3), file untouched" || bad "existing name refused"

# --- validation
sa_secret_gen 'Bad Name!' machine >/dev/null 2>&1; r1=$?; sa_secret_gen x bogusmode >/dev/null 2>&1; r2=$?; sa_secret_gen '../evil' machine >/dev/null 2>&1; r3=$?
{ [ $r1 -eq 64 ] && [ $r2 -eq 64 ] && [ $r3 -eq 64 ]; } && ok "bad name / unknown mode / path traversal -> 64" || bad "validation ($r1 $r2 $r3)"

# --- plan mode
reset; out=$(SA_MODE=plan sa_secret_gen pl machine 2>&1); rc=$?
{ [ $rc -eq 0 ] && [ ! -e "$SA_SECRETS_DIR" ] && [[ $out == plan:* ]]; } && ok "plan mode: nothing generated or written" || bad "plan mode"

# --- HIBP lookup logic
reset; _sa_secret_breached password; r1=$?
_sa_secret_breached 'definitely-not-breached-zzz'; r2=$?
touch "$T_FAIL"; _sa_secret_breached anything; r3=$?; rm "$T_FAIL"
{ [ $r1 -eq 0 ] && [ $r2 -eq 1 ] && [ $r3 -eq 2 ]; } && ok "HIBP: breached=0, clean=1, unreachable=2" || bad "HIBP logic ($r1 $r2 $r3)"
grep -q 'range/5BAA6$' "$FAKE_LOG" && ! grep -q '1E4C9B93F3F0' "$FAKE_LOG" && ok "HIBP: only the 5-char prefix is sent (k-anonymity)" || bad "HIBP k-anonymity"

# --- passphrase mode
reset; val=$(sa_secret_gen pp human-passphrase 2>/dev/null); rc=$?
IFS=- read -ra W <<<"$val"
{ [ $rc -eq 0 ] && [ ${#W[@]} -eq 6 ] && [ ${#val} -ge 15 ]; } && ok "passphrase: 6 words, >=15 chars" || bad "passphrase shape (rc=$rc n=${#W[@]})"
okw=1; for w in "${W[@]}"; do grep -qx -- "$w" "$SA_WORDLIST" || okw=0; done
[ $okw -eq 1 ] && ok "passphrase: every word is from the wordlist" || bad "passphrase words from wordlist"
{ grep -q -- '-id -t 2 -m 14 -p 1 -e' "$FAKE_ARGV" && [ "$(sed -n '1p' "$SA_SECRETS_DIR/pp.hash")" = '$argon2id$v=19$m=16384,t=2,p=1$FAKESALT$FAKEHASH' ]; } \
  && ok "passphrase: Argon2id (m=16 MiB, t=2, p=1) stored, not SHA-256" || bad "passphrase argon2 params/storage"
grep -qF -- "$val" "$FAKE_ARGV" && bad "password not in argv" || ok "password passed via stdin, not argv"
grep -rqF -- "$val" "$SA_SECRETS_DIR" && bad "passphrase NOT on disk" || ok "passphrase never written to disk"
[ "$(grep -c '^curl' "$FAKE_LOG")" = 1 ] && ok "passphrase: HIBP checked once" || bad "passphrase: HIBP checked once"

# retry on breach (override the lookup: first 2 draws 'breached')
reset; N=0; _sa_secret_breached() { N=$((N+1)); [ $N -le 2 ]; }
val=$(sa_secret_gen pp2 human-passphrase 2>/dev/null); rc=$?
# subshell hid N; verify via outcome only
[ $rc -eq 0 ] && [ -n "$val" ] && ok "breached draws are redrawn" || bad "breached draws redrawn (rc=$rc)"
_sa_secret_breached() { return 0; }                       # always breached
reset; sa_secret_gen pp3 human-passphrase >/dev/null 2>&1; rc=$?
{ [ $rc -eq 4 ] && [ ! -e "$SA_SECRETS_DIR/pp3.hash" ]; } && ok "all draws breached: rc 4, nothing stored" || bad "all draws breached (rc=$rc)"
source "$ROOT/lib/secret.sh"                              # restore real lookup

# HIBP unreachable => fail closed, nothing stored or printed
reset; touch "$T_FAIL"; out=$(sa_secret_gen pp4 human-passphrase 2>/dev/null); rc=$?; rm "$T_FAIL"
{ [ $rc -eq 6 ] && [ -z "$out" ] && [ ! -e "$SA_SECRETS_DIR/pp4.hash" ]; } && ok "HIBP unreachable: rc 6, nothing printed or stored" || bad "HIBP unreachable (rc=$rc)"

# wordlist problems
reset; SA_WORDLIST="$T/none.txt" sa_secret_gen w1 human-passphrase >/dev/null 2>&1; r1=$?
head -100 "$T/words.txt" > "$T/short.txt"; SA_WORDLIST="$T/short.txt" sa_secret_gen w2 human-passphrase >/dev/null 2>&1; r2=$?
SA_PASSPHRASE_WORDS=4 sa_secret_gen w3 human-passphrase >/dev/null 2>&1; r3=$?
{ [ $r1 -eq 5 ] && [ $r2 -eq 5 ] && [ $r3 -eq 64 ]; } && ok "missing/short wordlist -> 5; <6 words -> 64" || bad "wordlist checks ($r1 $r2 $r3)"

# argon2 missing => refuse, no weaker fallback
reset; mv "$T/bin/argon2" "$T/bin/argon2.off"
out=$(sa_secret_gen nf human-passphrase 2>/dev/null); rc=$?
{ [ $rc -eq 5 ] && [ -z "$out" ] && [ ! -e "$SA_SECRETS_DIR/nf.hash" ]; } && ok "argon2 missing: rc 5, no fallback hash, nothing printed" || bad "argon2 missing (rc=$rc)"
mv "$T/bin/argon2.off" "$T/bin/argon2"

# --- legacy mode
reset; val=$(sa_secret_gen lg human-legacy 2>/dev/null); rc=$?
{ [ $rc -eq 0 ] && [ ${#val} -eq 24 ] && [[ $val =~ ^[A-Za-z0-9_-]+$ ]] && [ ! -s "$FAKE_LOG" ] && grep -q -- '-id' "$FAKE_ARGV"; } \
  && ok "legacy: 24 chars, Argon2id, no HIBP call" || bad "legacy (rc=$rc len=${#val})"
SA_LEGACY_LEN=12 sa_secret_gen lg2 human-legacy >/dev/null 2>&1; [ $? -eq 4 ] && ok "legacy shorter than 20 refused" || bad "legacy shorter than 20 refused"

# --- list shows names only
reset; sa_secret_gen aaa machine >/dev/null 2>&1; sa_secret_gen bbb machine >/dev/null 2>&1
out=$(sa_secret_list | sort | tr '\n' ' ')
{ [ "$out" = "aaa bbb " ] && ! grep -q sha256 <<<"$out"; } && ok "list: names only, no hashes/values" || bad "list names only ('$out')"
reset; [ -z "$(sa_secret_list)" ] && ok "list on empty/missing dir is empty" || bad "list on empty dir"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
