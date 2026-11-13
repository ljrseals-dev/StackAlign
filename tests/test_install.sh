#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# install.sh's pins are not env-overridable, so tests run a COPY with the SHA line
# substituted. Fake curl serves fixtures; nothing touches the network.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/fix" "$T/tmp"
export TMPDIR="$T/tmp" FAKE_FIX="$T/fix" FAKE_CURL_LOG="$T/curl.log" FAKE_OUT="$T/bin.out"

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$FAKE_CURL_LOG"
out=""; url=""
while [ $# -gt 0 ]; do case $1 in -o) out=$2; shift ;; -*) ;; *) url=$1 ;; esac; shift; done
[ -e "$FAKE_FIX/curl_fail" ] && exit 22
cp "$FAKE_FIX/$(basename "$url")" "$out"
EOF
chmod +x "$T/bin/curl"; export PATH="$T/bin:$PATH"

VER=$(sed -n 's/^readonly VERSION="\(.*\)"/\1/p' "$ROOT/install.sh")
PKG="stackalign-$VER.tar.gz"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }

mkfix() {  # <bin-script-body> -> builds $T/fix/$PKG, echoes sha
  rm -rf "$T/src"; mkdir -p "$T/src/stackalign-$VER/bin"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$T/src/stackalign-$VER/bin/stackalign"
  chmod +x "$T/src/stackalign-$VER/bin/stackalign"
  tar -czf "$T/fix/$PKG" -C "$T/src" "stackalign-$VER"
  sha256sum "$T/fix/$PKG" | awk '{print $1}'
}
mkscript() {  # <sha> -> $T/install.test.sh (copy with SHA substituted)
  sed "s|^readonly EXPECTED_SHA256=.*|readonly EXPECTED_SHA256=\"$1\"|" "$ROOT/install.sh" > "$T/install.test.sh"
}
runi() { : > "$FAKE_CURL_LOG"; rm -f "$FAKE_OUT"; OUT=$(bash "$T/install.test.sh" "$@" 2>&1); RC=$?; }
curls() { grep -c '^curl' "$FAKE_CURL_LOG"; }

# 1. shipped skeleton refuses (PLACEHOLDER), no network
: > "$FAKE_CURL_LOG"; OUT=$(bash "$ROOT/install.sh" 2>&1); RC=$?
{ [ $RC -eq 3 ] && [[ $OUT == *PLACEHOLDER* ]] && [ "$(curls)" = 0 ]; } && ok "PLACEHOLDER sha: refused (rc 3), no download" || bad "PLACEHOLDER sha refused (rc=$RC)"

# 2. malformed sha refused
mkscript "notahash"; runi
{ [ $RC -eq 3 ] && [ "$(curls)" = 0 ]; } && ok "malformed sha: refused (rc 3), no download" || bad "malformed sha refused"

# 3. good fixture release: runs bin with 'install --apply' + passthrough args
sha=$(mkfix 'echo "ARGS: $*" > "$FAKE_OUT"'); mkscript "$sha"; runi extra1 extra2
{ [ $RC -eq 0 ] && [ "$(cat "$FAKE_OUT")" = "ARGS: install --apply extra1 extra2" ]; } && ok "good release: verified, extracted, ran 'install --apply' + args" || bad "good release (rc=$RC: $OUT)"

# 3b. --yes is moved before the command; other args keep their order
runi --yes extra1; { [ $RC -eq 0 ] && [ "$(cat "$FAKE_OUT")" = "ARGS: --yes install --apply extra1" ]; } && ok "--yes moved before 'install'" || bad "--yes moved before 'install' (rc=$RC: $(cat "$FAKE_OUT" 2>/dev/null))"
runi extra1 --yes extra2; [ "$(cat "$FAKE_OUT")" = "ARGS: --yes install --apply extra1 extra2" ] && ok "--yes extracted from the middle of args" || bad "--yes extracted from the middle"
runi; [ "$(cat "$FAKE_OUT")" = "ARGS: install --apply" ] && ok "no args: unchanged behaviour" || bad "no args unchanged"

# 4. exactly one download, from the pinned URL
{ [ "$(curls)" = 1 ] && grep -q "https://github.com/ljrseals-dev/stackalign/releases/download/v$VER/$PKG" "$FAKE_CURL_LOG"; } && ok "exactly one curl call, pinned URL" || bad "exactly one curl call, pinned URL"
grep -q -- '--proto =https' "$FAKE_CURL_LOG" && ok "curl forced to https" || bad "curl forced to https"

# 5. temp dir cleaned up
[ -z "$(ls -A "$T/tmp")" ] && ok "temp dir cleaned after success" || bad "temp dir cleaned after success"

# 6. corrupted tarball: sha mismatch, rc 4, bin never ran, nothing extracted
cp "$T/fix/$PKG" "$T/fix/$PKG.good"; printf 'X' >> "$T/fix/$PKG"
runi
{ [ $RC -eq 4 ] && [[ $OUT == *"SHA-256 mismatch"* ]] && [ ! -e "$FAKE_OUT" ]; } && ok "corrupted tarball: rc 4, mismatch reported, bin never ran" || bad "corrupted tarball (rc=$RC)"
[ -z "$(ls -A "$T/tmp")" ] && ok "temp dir cleaned after failure" || bad "temp dir cleaned after failure"
mv "$T/fix/$PKG.good" "$T/fix/$PKG"

# 7. wrong-content tarball (valid tar, different sha than pinned)
mkfix 'echo EVIL > "$FAKE_OUT"' >/dev/null; runi
{ [ $RC -eq 4 ] && [ ! -e "$FAKE_OUT" ]; } && ok "swapped release (different sha): refused" || bad "swapped release refused"

# 8. download failure
sha=$(mkfix 'true'); mkscript "$sha"; touch "$FAKE_FIX/curl_fail"; runi; rm "$FAKE_FIX/curl_fail"
{ [ $RC -eq 2 ] && [ ! -e "$FAKE_OUT" ]; } && ok "download failure: rc 2, nothing run" || bad "download failure (rc=$RC)"

# 9. path-traversal / absolute-path archives refused even with matching sha
for member in '../evil' '/tmp/evil-abs'; do
  python3 -I - "$T/fix/$PKG" "$member" "$VER" <<'PY'
import sys, tarfile, io
out, member, ver = sys.argv[1:4]
with tarfile.open(out, "w:gz") as t:
    for name, data in ((member, b"x"), (f"stackalign-{ver}/bin/stackalign", b"#!/bin/sh\ntrue\n")):
        ti = tarfile.TarInfo(name); ti.size = len(data); ti.mode = 0o755
        t.addfile(ti, io.BytesIO(data))
PY
  sha=$(sha256sum "$T/fix/$PKG" | awk '{print $1}'); mkscript "$sha"; runi
  { [ $RC -eq 5 ] && [[ $OUT == *"absolute or '..' paths"* ]] && [ ! -e "$T/evil" ]; } && ok "archive member '$member' refused (rc 5)" || bad "archive member '$member' (rc=$RC)"
done

# 9b. Reject symbolic and hard links even when the archive hash is pinned.
for linktype in symlink hardlink; do
  python3 -I - "$T/fix/$PKG" "$VER" "$linktype" <<'PY'
import io, sys, tarfile
out, ver, kind = sys.argv[1:4]
with tarfile.open(out, "w:gz") as t:
    root = f"stackalign-{ver}"
    payload = b"#!/bin/sh\\ntrue\\n"
    regular = tarfile.TarInfo(f"{root}/bin/payload")
    regular.size = len(payload)
    t.addfile(regular, io.BytesIO(payload))
    link = tarfile.TarInfo(f"{root}/bin/stackalign")
    if kind == "symlink":
        link.type = tarfile.SYMTYPE
        link.linkname = "/etc/passwd"
    else:
        link.type = tarfile.LNKTYPE
        link.linkname = f"{root}/bin/payload"
    t.addfile(link)
PY
  sha=$(sha256sum "$T/fix/$PKG" | awk '{print $1}'); mkscript "$sha"; runi
  { [ $RC -eq 5 ] && [[ $OUT == *"symbolic or hard links"* ]] && [ ! -e "$FAKE_OUT" ]; } \\
    && ok "archive $linktype refused before extraction (rc 5)" || bad "archive $linktype refused (rc=$RC: $OUT)"
done

# 10. exit code of bin/stackalign is propagated
sha=$(mkfix 'exit 7'); mkscript "$sha"; runi
[ $RC -eq 7 ] && ok "bin/stackalign exit code propagated (7)" || bad "exit code propagated (rc=$RC)"

# 11. missing bin/stackalign in release
rm -rf "$T/src"; mkdir -p "$T/src/stackalign-$VER"; echo hi > "$T/src/stackalign-$VER/README"
tar -czf "$T/fix/$PKG" -C "$T/src" "stackalign-$VER"; sha=$(sha256sum "$T/fix/$PKG" | awk '{print $1}'); mkscript "$sha"; runi
[ $RC -eq 5 ] && ok "release without bin/stackalign refused (rc 5)" || bad "release without bin/stackalign (rc=$RC)"

# 12. static properties of the shipped script
code=$(grep -vE '^[[:space:]]*#' "$ROOT/install.sh")
[ "$(grep -c 'curl ' <<<"$code")" = 1 ] && ok "static: exactly one curl in code" || bad "static: exactly one curl"
grep -qE 'eval|\| *(ba)?sh' <<<"$code" && bad "static: no eval / pipe-to-shell" || ok "static: no eval / pipe-to-shell"
grep -qE 'SA_[A-Z_]*:-|\$\{(VERSION|EXPECTED_SHA256|BASE_URL):-' <<<"$code" && bad "static: pins not env-overridable" || ok "static: pins not env-overridable"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
