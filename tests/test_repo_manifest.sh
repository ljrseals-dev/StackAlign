#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_repo_manifest.sh -- manifest pin resolution and fail-closed installs.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/bin" "$T/repos"
export PATH="$T/bin:$PATH" SA_ROOT="$ROOT" SA_YUM_REPOS_DIR="$T/repos"
export CALLS="$T/calls" SA_VERSIONS_TOML="$T/versions.toml"
: > "$CALLS"
cat > "$T/bin/dnf" <<'FAKE'
#!/usr/bin/env bash
printf 'dnf %s\n' "$*" >> "$CALLS"
exit 0
FAKE
cat > "$T/bin/rpm" <<'FAKE'
#!/usr/bin/env bash
printf 'rpm %s\n' "$*" >> "$CALLS"
case "${1:-}" in
  -q) exit 0 ;;
  *) exit 0 ;;
esac
FAKE
chmod +x "$T/bin/"*
. "$ROOT/lib/repo.sh"

fail=0
check() {
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"
  else printf "FAIL %s (got '%s' want '%s')\n" "$1" "$2" "$3"; fail=1
  fi
}
write_manifest() {
  cat > "$SA_VERSIONS_TOML"
}

write_manifest <<'TOML'
[[component]]
name = "nginx"
pinned_version = "1.30.6"
tested_matrix = ""

[[component]]
name = "php"
pinned_version = "8.5.12"
tested_matrix = ""
TOML

pin=$(_sa_repo_manifest_pin nginx 2>/dev/null); rc=$?
check "exact component pin resolved" "$rc:$pin" "0:1.30.6"
pin=$(_sa_repo_manifest_pin php 2>/dev/null); rc=$?
check "second array-table pin resolved" "$rc:$pin" "0:8.5.12"
pin=$(_sa_repo_manifest_pin NGINX 2>/dev/null); rc=$?
check "component match is case-sensitive" "$rc" 67

# Install accepts the pinned keyword and uses the manifest version.
: > "$CALLS"
touch "$SA_YUM_REPOS_DIR/stackalign-nginx.repo"
sa_repo_install nginx nginx pinned >/dev/null 2>&1; rc=$?
check "pinned install succeeds" "$rc" 0
grep -q 'dnf install -y -- nginx-1.30.6' "$CALLS"; check "pinned version reaches DNF" "$?" 0
grep -q 'dnf versionlock add -- nginx-1.30.6' "$CALLS"; check "pinned version is locked" "$?" 0

# An explicit listed version must match the manifest.
: > "$CALLS"
sa_repo_install nginx nginx 1.30.5 >/dev/null 2>&1; rc=$?
check "explicit pin mismatch refused" "$rc" 65
grep -q '^dnf ' "$CALLS"; check "mismatch refused before DNF" "$?" 1

# Explicit versions remain supported for unlisted components.
write_manifest <<'TOML'
[[component]]
name = "nginx"
pinned_version = "1.30.6"
TOML
touch "$SA_YUM_REPOS_DIR/stackalign-custom.repo"
sa_repo_install custom custom 2.4.0 >/dev/null 2>&1; rc=$?
check "unlisted explicit version remains supported" "$rc" 0

# Duplicate component names are ambiguous and fail closed.
write_manifest <<'TOML'
[[component]]
name = "nginx"
pinned_version = "1.30.6"
[[component]]
name = "nginx"
pinned_version = "1.30.7"
TOML
: > "$CALLS"
sa_repo_install nginx nginx pinned >/dev/null 2>&1; rc=$?
check "duplicate component pin refused" "$rc" 65
grep -q '^dnf ' "$CALLS"; check "duplicate manifest refused before DNF" "$?" 1

# A malformed manifest fails closed even for an explicit version.
printf '[[component]]\nname = "nginx"\npinned_version = []\n' > "$SA_VERSIONS_TOML"
sa_repo_install nginx nginx 1.30.6 >/dev/null 2>&1; rc=$?
check "malformed manifest refuses explicit version" "$rc" 65

# Missing manifest: explicit version remains backward compatible; pinned fails.
rm -f "$SA_VERSIONS_TOML"
sa_repo_install custom custom 2.4.0 >/dev/null 2>&1; rc=$?
check "missing manifest permits explicit version" "$rc" 0
sa_repo_install custom custom pinned >/dev/null 2>&1; rc=$?
check "missing manifest refuses pinned version" "$rc" 65

exit "$fail"
