#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Fake curl tests for lib/fetch.sh. No network or package manager is used.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d) || exit 1
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/bin" "$T/out"
export FETCH_LOG="$T/curl.log"

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
url=""
while [ $# -gt 0 ]; do
  case $1 in
    --output|-o) out=$2; shift 2 ;;
    --) shift; url=$1; break ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >> "$FETCH_LOG"
case $url in
  *primary-ok*|*mirror-ok*)
    printf 'verified payload\n' > "$out"
    exit 0
    ;;
  *key-multi*)
    printf '%s\n' \
      'pub:-:2048:1:PRIMARY:::::::::' \
      'fpr:::::::::0123456789ABCDEF0123456789ABCDEF01234567:' \
      'uid:-:::::::Primary Key:' \
      'pub:-:2048:1:SECONDARY:::::::::' \
      'fpr:::::::::BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB:' > "$out"
    exit 0
    ;;
  *key-subkey*)
    printf '%s\n' \
      'pub:-:2048:1:PRIMARY:::::::::' \
      'fpr:::::::::0123456789ABCDEF0123456789ABCDEF01234567:' \
      'uid:-:::::::Primary Key:' \
      'sub:-:2048:1:SUBKEY:::::::::' \
      'fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:' > "$out"
    exit 0
    ;;
  *primary-fail*|*mirror-fail*|*allfail*)
    printf 'partial bytes\n' > "$out"
    exit 22
    ;;
  *)
    printf 'unexpected fake URL: %s\n' "$url" >&2
    exit 90
    ;;
esac
EOF
chmod 0755 "$T/bin/curl"
cat > "$T/bin/gpg" <<'EOF'
#!/usr/bin/env bash
key_file="${@: -1}"
cat -- "$key_file"
EOF
chmod 0755 "$T/bin/gpg"
PATH="$T/bin:$PATH"
export PATH
# shellcheck disable=SC1091
source "$ROOT/lib/fetch.sh"

pass=0
fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }

# Primary success publishes the completed file.
: > "$FETCH_LOG"
if sa_fetch_url https://example.invalid/primary-ok "$T/out/primary"; then
  [ "$(cat "$T/out/primary")" = "verified payload" ] && ok "primary success publishes exact bytes" || bad "primary success bytes"
else
  bad "primary success returned failure"
fi
[ "$(wc -l < "$FETCH_LOG")" -eq 1 ] && ok "primary success does not contact mirrors" || bad "primary success mirror count"

# Primary failure followed by mirror failures/success proves ordered failover.
: > "$FETCH_LOG"
if sa_fetch_url https://example.invalid/primary-fail "$T/out/fallback" \
    https://example.invalid/mirror-fail https://example.invalid/mirror-ok; then
  [ "$(cat "$T/out/fallback")" = "verified payload" ] && ok "fallback success publishes complete mirror bytes" || bad "fallback bytes"
else
  bad "fallback sequence returned failure"
fi
expected_log=$(printf '%s\n' \
  https://example.invalid/primary-fail \
  https://example.invalid/mirror-fail \
  https://example.invalid/mirror-ok)
[ "$(cat "$FETCH_LOG")" = "$expected_log" ] && ok "sources attempted in declared order" || bad "source order"

# All failures must not publish partial bytes or replace an existing output.
printf 'keep old\n' > "$T/out/preserved"
if sa_fetch_url https://example.invalid/allfail "$T/out/preserved" \
    https://example.invalid/allfail; then
  bad "all-fail sequence unexpectedly succeeded"
else
  [ "$(cat "$T/out/preserved")" = "keep old" ] && ok "all failures preserve existing output" || bad "existing output changed on failure"
fi
if sa_fetch_url https://example.invalid/allfail "$T/out/not-published"; then
  bad "all-fail sequence published output"
else
  [ ! -e "$T/out/not-published" ] && ok "all failures publish no partial output" || bad "partial output left behind"
fi
leftovers=$(find "$T/out" -maxdepth 1 -name '.*.sa-fetch.*' -print)
[ -z "$leftovers" ] && ok "temporary downloads cleaned up" || bad "temporary downloads remain"

# Scheme validation happens before curl is invoked.
: > "$FETCH_LOG"
if sa_fetch_url http://example.invalid/plain "$T/out/http"; then
  bad "plain HTTP URL accepted"
else
  [ ! -s "$FETCH_LOG" ] && ok "non-HTTPS URL rejected before curl" || bad "curl invoked for HTTP URL"
fi

# SHA-256 verifies bytes and rejects malformed or incorrect expected values.
digest=$(sha256sum "$T/out/primary")
digest=${digest:0:64}
sa_fetch_verify "$T/out/primary" "$digest" && ok "matching SHA-256 accepted" || bad "matching SHA-256 rejected"
if sa_fetch_verify "$T/out/primary" "0000000000000000000000000000000000000000000000000000000000000000"; then
  bad "mismatched SHA-256 accepted"
else
  ok "mismatched SHA-256 rejected"
fi
if sa_fetch_verify "$T/out/primary" "not-a-digest"; then
  bad "malformed SHA-256 accepted"
else
  ok "malformed SHA-256 rejected"
fi

# Do not follow an output symlink.
ln -s "$T/out/primary" "$T/out/link"
if sa_fetch_url https://example.invalid/primary-ok "$T/out/link"; then
  bad "symlink output path accepted"
else
  [ -L "$T/out/link" ] && ok "symlink output path rejected without following it" || bad "symlink output path altered"
fi


# T33: reject a key bundle containing two primary pub records.
if sa_fetch_gpg_key https://example.invalid/key-multi \
    0123456789ABCDEF0123456789ABCDEF01234567 "$T/out/multi.asc" 2>"$T/multi.err"; then
  bad "T33 multi-primary key bundle accepted"
else
  if grep -q 'error=gpg_key_multi_pub:2' "$T/multi.err" && [ ! -e "$T/out/multi.asc" ]; then
    ok "T33 exactly one primary pub record required"
  else
    bad "T33 multi-primary rejection or cleanup"
  fi
fi

# T34: accept the primary fingerprint, not the later subkey fingerprint.
if sa_fetch_gpg_key https://example.invalid/key-subkey \
    0123456789ABCDEF0123456789ABCDEF01234567 "$T/out/primary-key.asc"; then
  ok "T34 primary fingerprint accepted with a distinct subkey fingerprint"
else
  bad "T34 primary fingerprint was not selected"
fi

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
