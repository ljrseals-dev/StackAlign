#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_repo_toml.sh -- manifest-driven pin resolution in sa_repo_install.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/repos"; : > "$T/calls"
export CALLS="$T/calls" STATE="$T/installed" PATH="$T/bin:$PATH" SA_YUM_REPOS_DIR="$T/repos"
: > "$T/repos/stackalign-nginx.repo"; : > "$T/repos/stackalign-php.repo"

cat > "$T/bin/dnf" <<'F'
#!/usr/bin/env bash
echo "dnf $*" >> "$CALLS"
[ "$1" = install ] && printf '%s\n' "${@: -1}" >> "$STATE"
exit 0
F
cat > "$T/bin/rpm" <<'F'
#!/usr/bin/env bash
[ "$1" = -q ] && grep -qx -- "$2" "$STATE" 2>/dev/null
F
chmod +x "$T/bin/"*

export SA_ROOT="$ROOT"
. "$ROOT/lib/repo.sh"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2' want '$3')"; fail=1; fi; }
reset() { : > "$CALLS"; rm -f "$STATE"; }
M="$T/versions.toml"
cp "$ROOT/vendor/versions.toml" "$M"
export SA_VERSIONS_TOML="$M"

reset; sa_repo_install nginx nginx pinned >/dev/null 2>&1; rc=$?
check "pinned resolves + installs" "$rc" 0
grep -q "dnf install -y -- nginx-1.30.6" "$CALLS"; check "dnf got manifest version" "$?" 0
grep -q "versionlock add -- nginx-1.30.6" "$CALLS"; check "versionlock uses pin" "$?" 0

reset; sa_repo_install nginx nginx 1.30.6 >/dev/null 2>&1; check "explicit == pin ok" "$?" 0
reset; sa_repo_install nginx nginx 1.29.0 >/dev/null 2>&1; check "explicit != pin refused (65)" "$?" 65
check "no dnf on mismatch" "$(wc -l < "$CALLS" | tr -d ' ')" 0

reset; sa_repo_install bogus nginx pinned >/dev/null 2>&1; check "unknown component, pinned (65)" "$?" 65

printf '%s\n' '[[component]]' 'name = "nginx"' 'pinned_version = "1.30.6"' \
  '[[component]]' 'name = "nginx"' 'pinned_version = "1.99.0"' > "$M"
reset; sa_repo_install nginx nginx pinned >/dev/null 2>&1; check "duplicate component (65)" "$?" 65

printf '%s\n' '[[component]]' 'name = "nginx"' 'pinned_version = "1.30.6"' 'tested_matrix = []' > "$M"
reset; sa_repo_install nginx nginx pinned >/dev/null 2>&1; check "array value => parse fail (65)" "$?" 65
reset; sa_repo_install nginx nginx 1.30.6 >/dev/null 2>&1; check "broken manifest fails closed even w/ explicit ver" "$?" 65

printf '%s\n' '[[component]]' 'name = "nginx"' 'pinned_version = "1.0/../x"' > "$M"
reset; sa_repo_install nginx nginx pinned >/dev/null 2>&1; check "invalid pinned_version (65)" "$?" 65

printf '%s\n' '[[component]]' 'name = "nginx"' 'channel = "stable"' > "$M"
reset; sa_repo_install nginx nginx pinned >/dev/null 2>&1; check "missing pinned_version (65)" "$?" 65

export SA_VERSIONS_TOML="$T/absent.toml"
reset; sa_repo_install nginx nginx pinned >/dev/null 2>&1; check "no manifest + pinned (65)" "$?" 65
reset; sa_repo_install nginx nginx 1.30.6 >/dev/null 2>&1; check "no manifest + explicit: legacy path ok" "$?" 0

cp "$ROOT/vendor/versions.toml" "$M"; export SA_VERSIONS_TOML="$M"
reset; sa_repo_install php php-fpm 8.5.12 >/dev/null 2>&1; check "unlisted-by-name pkg, repo name php matches" "$?" 0
reset; sa_repo_install nginx nginx 'pinned; rm' >/dev/null 2>&1; check "injection-shaped version rejected (64)" "$?" 64
exit "$fail"
