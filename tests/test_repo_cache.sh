#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_repo_cache.sh -- exact-NEVRA verification for sa_cache_get.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; : > "$T/calls"
export CALLS="$T/calls" PATH="$T/bin:$PATH" SA_RPM_CACHE="$T/cache"

# Fake rpm file content == its NEVRA. FAKE_FILES="name:content name:content".
cat > "$T/bin/dnf" <<'FAKE'
#!/usr/bin/env bash
echo "dnf $*" >> "$CALLS"
dest=""; while [ "$#" -gt 0 ]; do [ "$1" = --destdir ] && dest="$2"; shift; done
for spec in $FAKE_FILES; do printf '%s' "${spec#*:}" > "$dest/${spec%%:*}.rpm"; done
exit 0
FAKE
cat > "$T/bin/rpm" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  --checksig) [ "${FAKE_SIG_BAD:-0}" = 1 ] && exit 1; exit 0 ;;
  -qp) cat "${@: -1}" ;;
esac
FAKE
chmod +x "$T/bin/"*
. "$ROOT/lib/repo_cache.sh"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2' want '$3')"; fail=1; fi; }
W=pkg-2.0-1.x86_64

export FAKE_FILES="a:$W"
out="$(sa_cache_get "$W" 2>/dev/null)"; rc=$?
check "download ok"            "$rc" 0
check "stdout is path only"    "$out" "$SA_RPM_CACHE/$W.rpm"
: > "$CALLS"; sa_cache_get "$W" >/dev/null 2>&1
check "hit skips dnf"          "$(wc -l < "$CALLS" | tr -d ' ')" 0

rm -rf "$SA_RPM_CACHE"; export FAKE_FILES="a:pkg-9.9-1.x86_64"
sa_cache_get "$W" >/dev/null 2>&1; check "wrong NEVRA rejected" "$?" 1
check "nothing cached on reject" "$(ls "$SA_RPM_CACHE" | wc -l | tr -d ' ')" 0

export FAKE_FILES="a:$W b:$W"
sa_cache_get "$W" >/dev/null 2>&1; check "two RPMs rejected" "$?" 1

export FAKE_FILES="a:$W" FAKE_SIG_BAD=1
sa_cache_get "$W" >/dev/null 2>&1; check "bad signature rejected" "$?" 1
unset FAKE_SIG_BAD

for bad in "../x" "a/b" 'a*b' "-rf" "" "a b"; do
  sa_cache_get "$bad" >/dev/null 2>&1; check "invalid nevra '$bad'" "$?" 1
done
check "no temp dirs left" "$(ls -A "$SA_RPM_CACHE" | grep -c '^\.dl\.')" 0

# corrupt cache entry (wrong NEVRA inside right filename) is not trusted
printf 'pkg-0.1-1.x86_64' > "$SA_RPM_CACHE/$W.rpm"; export FAKE_FILES="a:$W"
sa_cache_get "$W" >/dev/null 2>&1; check "bad hit refetched" "$?" 0
check "refetched content correct" "$(cat "$SA_RPM_CACHE/$W.rpm")" "$W"
exit "$fail"
