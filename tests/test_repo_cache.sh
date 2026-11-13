#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_repo_cache.sh -- exact-NEVRA and signature verification for sa_cache_get.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/bin" || exit 1
: > "$T/calls"
export CALLS="$T/calls" PATH="$T/bin:$PATH" SA_RPM_CACHE="$T/cache"

# Fake RPM files contain their queried NEVRA. FAKE_FILES is a
# space-separated list of filename:NEVRA pairs.
cat > "$T/bin/dnf" <<'FAKE'
#!/usr/bin/env bash
printf 'dnf %s\n' "$*" >> "$CALLS"
dest=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = --destdir ]; then
        [ "$#" -ge 2 ] || exit 64
        dest=$2
        shift 2
    else
        shift
    fi
done
[ -n "$dest" ] || exit 64
for spec in ${FAKE_FILES:-}; do
    name=${spec%%:*}
    nevra=${spec#*:}
    printf '%s' "$nevra" > "$dest/$name.rpm" || exit 1
done
FAKE
cat > "$T/bin/rpm" <<'FAKE'
#!/usr/bin/env bash
case ${1:-} in
    --checksig)
        [ "$#" -eq 2 ] || exit 64
        base=${2##*/}
        case " ${FAKE_BAD_SIG_FILES:-} " in
            *" $base "*) exit 1 ;;
        esac
        exit 0
        ;;
    -qp)
        [ "$#" -eq 4 ] || exit 64
        [ "$2" = --qf ] && [ "$3" = '%{NEVRA}' ] || exit 64
        cat -- "$4"
        ;;
    *)
        echo "unexpected fake rpm arguments: $*" >&2
        exit 64
        ;;
esac
FAKE
chmod +x "$T/bin/dnf" "$T/bin/rpm"
. "$ROOT/lib/repo_cache.sh"

fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf 'ok   %s\n' "$1"
    else
        printf "FAIL %s (got '%s' want '%s')\n" "$1" "$2" "$3"
        fail=1
    fi
}
count_files() {
    find "$SA_RPM_CACHE" -mindepth 1 -maxdepth 1 -type f ! -name '.dl.*' -print 2>/dev/null | wc -l | tr -d ' '
}
count_tempdirs() {
    find "$SA_RPM_CACHE" -mindepth 1 -maxdepth 1 -type d -name '.dl.*' -print 2>/dev/null | wc -l | tr -d ' '
}
W='pkg-2.0-1.x86_64'

export FAKE_FILES="a:$W"
out="$(sa_cache_get "$W" 2>/dev/null)"; rc=$?
check "download ok" "$rc" 0
check "stdout is exact path only" "$out" "$SA_RPM_CACHE/$W.rpm"
check "downloaded content is exact NEVRA" "$(cat "$SA_RPM_CACHE/$W.rpm" 2>/dev/null)" "$W"

: > "$CALLS"
sa_cache_get "$W" >/dev/null 2>&1; rc=$?
check "verified cache hit succeeds" "$rc" 0
check "verified cache hit skips dnf" "$(wc -l < "$CALLS" | tr -d ' ')" 0

# A cache hit with a bad signature must not be trusted; a valid download
# under a different temporary filename should replace it.
export FAKE_BAD_SIG_FILES="$W.rpm" FAKE_FILES="fresh:$W"
: > "$CALLS"
out="$(sa_cache_get "$W" 2>/dev/null)"; rc=$?
check "bad-signature cache entry refetched" "$rc" 0
check "bad-signature cache entry triggered dnf" "$(wc -l < "$CALLS" | tr -d ' ')" 1
check "replacement content is exact NEVRA" "$(cat "$SA_RPM_CACHE/$W.rpm" 2>/dev/null)" "$W"
unset FAKE_BAD_SIG_FILES

# A downloaded RPM with an invalid signature is rejected and not cached.
rm -f -- "$SA_RPM_CACHE/$W.rpm"
export FAKE_FILES="a:$W" FAKE_BAD_SIG_FILES="a.rpm"
sa_cache_get "$W" >/dev/null 2>&1; rc=$?
check "bad download signature rejected" "$rc" 1
check "bad-signature download not cached" "$(count_files)" 0
check "bad-signature temp directory cleaned" "$(count_tempdirs)" 0
unset FAKE_BAD_SIG_FILES

# A correctly signed RPM for another NEVRA must be rejected.
export FAKE_FILES="a:pkg-9.9-1.x86_64"
sa_cache_get "$W" >/dev/null 2>&1; rc=$?
check "wrong downloaded NEVRA rejected" "$rc" 1
check "wrong NEVRA not cached" "$(count_files)" 0
check "wrong NEVRA temp directory cleaned" "$(count_tempdirs)" 0

# Ambiguous downloads are rejected and every candidate is cleaned up.
export FAKE_FILES="a:$W b:$W"
sa_cache_get "$W" >/dev/null 2>&1; rc=$?
check "two RPMs rejected" "$rc" 1
check "ambiguous download not cached" "$(count_files)" 0
check "ambiguous download temp directory cleaned" "$(count_tempdirs)" 0

for bad in "../x" "a/b" 'a*b' "-rf" "" "a b" "a?b" "a[b]"; do
    sa_cache_get "$bad" >/dev/null 2>&1; rc=$?
    check "invalid NEVRA '$bad'" "$rc" 64
done

# Corrupt content at the exact cache filename must trigger a fresh download.
export FAKE_FILES="fresh:$W"
printf 'pkg-0.1-1.x86_64' > "$SA_RPM_CACHE/$W.rpm"
: > "$CALLS"
sa_cache_get "$W" >/dev/null 2>&1; rc=$?
check "corrupt cache entry refetched" "$rc" 0
check "corrupt cache entry triggered dnf" "$(wc -l < "$CALLS" | tr -d ' ')" 1
check "refetched content correct" "$(cat "$SA_RPM_CACHE/$W.rpm")" "$W"
check "no temporary download directories remain" "$(count_tempdirs)" 0

exit "$fail"
