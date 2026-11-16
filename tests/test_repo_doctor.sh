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
printf '%s\n' "$*" >>"$SA_DNF_CALL_LOG"
[ "${1:-}" = --version ] && { echo 4.14.0; exit 0; }
echo "unexpected dnf invocation: $*" >&2
exit 99
EOF
chmod +x "$T/bin/dnf"
export PATH="$T/bin:$PATH" SA_OS_RELEASE_FILE="$T/os-release" SA_YUM_REPOS_DIR="$T/repos" SA_DNF_CALL_LOG="$T/dnf.log"
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

# Snapshot directory and every file: content hashes, sizes, mtimes, and names.
snapshot() {
  {
    find "$T/repos" -mindepth 0 -printf '%P|%y|%s|%T@\n' | LC_ALL=C sort
    find "$T/repos" -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
  }
}
before=$(snapshot)
out=$(sa_repo_doctor --section repo)
[[ "$out" == *"[PASS] REPO-001"* ]]
[[ "$out" == *"[PASS] REPO-002"* ]]
[[ "$out" == *"[PASS] REPO-003"* ]]
[[ "$out" == *"[PASS] REPO-004"* ]]
[[ "$out" == *"[SKIP] REPO-005"* ]]
[[ "$out" == *"[SKIP] REPO-006"* ]]
[[ "$out" == *"[SKIP] REPO-008"* ]]
[[ "$out" == *"[SKIP] REPO-009"* ]]
after=$(snapshot)
[[ "$before" == "$after" ]] || { echo "doctor changed repository directory contents or metadata" >&2; exit 1; }

json=$(sa_repo_doctor --section repo --json)
printf '%s\n' "$json" >"$T/doctor.json"
python3 - "$ROOT" "$T/doctor.json" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
data = json.loads(pathlib.Path(sys.argv[2]).read_text())
schema = json.loads((root / "lib/schemas/repo-doctor.v1.schema.json").read_text())
try:
    import jsonschema
except ImportError as exc:
    raise SystemExit("jsonschema is required for doctor contract validation") from exc
jsonschema.Draft202012Validator.check_schema(schema)
jsonschema.validate(data, schema, format_checker=jsonschema.Draft202012Validator.FORMAT_CHECKER)
assert data["summary"]["overall"] == "PASS"
assert [c["id"] for c in data["checks"]] == [f"REPO-{i:03d}" for i in range(1, 10)]
assert all({"id", "status", "details"} <= set(c) for c in data["checks"])
PY

# A WARN is non-fatal normally and becomes exit 2 under --strict.
cat >"$T/repos/sample.repo" <<'EOF'
[disabled]
enabled=0
EOF
set +e
sa_repo_doctor --section repo >/dev/null 2>&1; non_strict_rc=$?
sa_repo_doctor --section repo --strict >/dev/null 2>&1; strict_rc=$?
set -e
[[ "$non_strict_rc" -eq 0 ]]
[[ "$strict_rc" -eq 2 ]]

# Missing/unreadable OS release input is a detection error (exit 6).
SA_OS_RELEASE_FILE="$T/missing-os-release" sa_repo_doctor --section repo >/dev/null 2>&1 && {
  echo "expected missing OS release input to fail" >&2; exit 1;
} || rc=$?
[[ "${rc:-0}" -eq 6 ]]

# Malformed repository configuration is a hard failure (exit 2).
cat >"$T/repos/sample.repo" <<'EOF'
[broken]
this is not a key=value line
EOF
set +e
sa_repo_doctor --section repo >/dev/null 2>&1; malformed_rc=$?
set -e
[[ "$malformed_rc" -eq 2 ]]

# Backend discovery may ask for the version only; it must never refresh metadata.
[[ -f "$SA_DNF_CALL_LOG" ]]
[[ "$(cat "$SA_DNF_CALL_LOG")" == "--version" ]]

# The supplied parser fixtures belong to the upcoming status-parser phase. Ensure
# they remain present, but do not claim this doctor currently parses them.
grep -q 'Repo-id.*appstream' "$ROOT/tests/fixtures/el9_dnf_repoquery.txt"
grep -q 'Repo-id.*base' "$ROOT/tests/fixtures/centos7_yum_repos.txt"
grep -q '"schema":"stackalign.repo.status/v1"' "$ROOT/tests/fixtures/repo_status_expected.json"

echo "repo doctor tests: ok"
