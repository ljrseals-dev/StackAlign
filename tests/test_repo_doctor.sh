#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/repos"
cat >"$T/os-release" <<'EOF'
ID=almalinux
VERSION_ID=9.4
EOF
cat >"$T/bin/dnf" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo 4.14.0; exit 0; }
exit 0
EOF
chmod +x "$T/bin/dnf"
export PATH="$T/bin:$PATH" SA_OS_RELEASE_FILE="$T/os-release" SA_YUM_REPOS_DIR="$T/repos"
source "$ROOT/lib/repo_doctor.sh"

cat >"$T/repos/sample.repo" <<'EOF'
[baseos]
name=Base OS
enabled=1
gpgcheck=1

[disabled]
name=Disabled
enabled=0
EOF
before=$(sha256sum "$T/repos/sample.repo")
out=$(sa_repo_doctor --section repo)
[[ "$out" == *"[PASS] REPO-001"* ]]
[[ "$out" == *"[PASS] REPO-002"* ]]
[[ "$out" == *"[PASS] REPO-003"* ]]
[[ "$out" == *"[PASS] REPO-004"* ]]
[[ "$out" == *"[SKIP] REPO-005"* ]]
[[ "$out" == *"[SKIP] REPO-006"* ]]
after=$(sha256sum "$T/repos/sample.repo")
[[ "$before" == "$after" ]]

json=$(sa_repo_doctor --section repo --json)
python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="stackalign.repo.doctor/v1"; assert len(d["checks"])==9; assert d["summary"]["pass"] >= 4' <<<"$json"

cat >"$T/repos/sample.repo" <<'EOF'
[broken]
this is not a key=value line
EOF
if sa_repo_doctor --section repo >/dev/null 2>&1; then
  echo "expected malformed repo file to fail" >&2; exit 1
fi

: >"$T/repos/sample.repo"
if sa_repo_doctor --section repo --strict >/dev/null 2>&1; then
  echo "expected strict zero-enabled warning to fail" >&2; exit 1
fi

echo "repo doctor tests: ok"
