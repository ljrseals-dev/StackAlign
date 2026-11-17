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
# shellcheck source=../lib/repo_doctor.sh
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
validator_cls = jsonschema.validators.validator_for(schema)
validator_cls.check_schema(schema)
format_checker = getattr(validator_cls, "FORMAT_CHECKER", jsonschema.FormatChecker())
validator_cls(schema, format_checker=format_checker).validate(data)
assert data["summary"]["overall"] == "PASS"
assert [c["id"] for c in data["checks"]] == [f"REPO-{i:03d}" for i in range(1, 10)]
assert all({"id", "status", "details"} <= set(c) for c in data["checks"])
PY


# OS-release input is data, not shell code; quoted fields remain supported.
printf 'ID=almalinux\nVERSION_ID="9.4"\nNAME="AlmaLinux"\ntouch %q\n' "$T/os-release-executed" > "$T/malicious-os-release"
SA_OS_RELEASE_FILE="$T/malicious-os-release" sa_repo_doctor --section repo >/dev/null
[[ ! -e "$T/os-release-executed" ]] || { echo "OS-release parser executed file content" >&2; exit 1; }

# CentOS 8 must not be mislabeled as CentOS 7 or CentOS Stream.
cat > "$T/centos8-release" <<'EOF'
ID=centos
VERSION_ID="8"
NAME="CentOS Linux"
EOF
out=$(SA_OS_RELEASE_FILE="$T/centos8-release" sa_repo_doctor --section repo 2>&1)
[[ "$out" == *"CentOS Linux 8 is EOL"* ]]
[[ "$out" != *"CentOS 7 is EOL"* ]]

# CentOS 7 Vault eligibility is not asserted without a validated Vault source.
cat > "$T/centos7-release" <<'EOF'
ID=centos
VERSION_ID=7
NAME="CentOS Linux"
EOF
json=$(SA_OS_RELEASE_FILE="$T/centos7-release" sa_repo_doctor --section repo --json)
[[ "$json" == *'"vault_eligible":false'* ]]
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


# Invalid enabled values must fail syntax inspection and must not count as enabled.
cat > "$T/repos/sample.repo" <<'EOF'
[baseos]
enabled=maybe
EOF
set +e
sa_repo_doctor --section repo >"$T/invalid-enabled.out" 2>&1; invalid_enabled_rc=$?
set -e
[[ "$invalid_enabled_rc" -eq 2 ]]
grep -q '\[FAIL\] REPO-003' "$T/invalid-enabled.out"
# Backend discovery may ask for the version only; it must never refresh metadata.
[[ -f "$SA_DNF_CALL_LOG" ]]
grep -q . "$SA_DNF_CALL_LOG"
! grep -vqx -- "--version" "$SA_DNF_CALL_LOG"

# Captured DNF/YUM output is parsed deterministically without invoking dnf/yum.
dnf_json=$(sa_repo_parse_status_fixture dnf "$ROOT/tests/fixtures/el9_dnf_repoquery.txt")
printf '%s\n' "$dnf_json" >"$T/dnf-parsed.json"
yum_json=$(sa_repo_parse_status_fixture yum "$ROOT/tests/fixtures/centos7_yum_repos.txt")
printf '%s\n' "$yum_json" >"$T/yum-parsed.json"
python3 - "$T/dnf-parsed.json" "$T/yum-parsed.json" <<'PY'
import json, pathlib, sys
dnf = json.loads(pathlib.Path(sys.argv[1]).read_text())
yum = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert dnf["backend"] == "dnf"
repos = {r["id"]: r for r in dnf["repos"]}
assert list(repos) == ["appstream", "baseos", "crb", "epel"]
assert repos["appstream"]["source"] == "baseurl"
assert repos["appstream"]["enabled"] is None  # absent in captured output: do not guess
assert repos["crb"]["enabled"] is False
assert repos["epel"]["source"] == "metalink"
assert repos["epel"]["file"] == "/etc/yum.repos.d/epel.repo"
assert yum["backend"] == "yum"
legacy = {r["id"]: r for r in yum["repos"]}
assert list(legacy) == ["base", "updates", "extras"]
assert legacy["base"]["source"] == "mirrorlist"
assert legacy["base"]["enabled"] is None
assert legacy["base"]["health"] == "ERROR (EOL mirrorlist)"
assert legacy["updates"]["health"] == "ERROR"
PY
# The parser is read-only, rejects symlink input, and never calls package tools.
ln -s "$ROOT/tests/fixtures/el9_dnf_repoquery.txt" "$T/fixture-link"
set +e
sa_repo_parse_status_fixture dnf "$T/fixture-link" >/dev/null 2>&1; parser_link_rc=$?
set -e
[[ "$parser_link_rc" -eq 66 ]]

# Symlinked .repo files and failed backend probes are visible failures.
cat >"$T/repos/sample.repo" <<'EOF'
[baseos]
enabled=1
EOF
ln -s "$T/repos/sample.repo" "$T/repos/linked.repo"
set +e
sa_repo_doctor --section repo >"$T/symlink-repo.out" 2>&1; symlink_repo_rc=$?
set -e
[[ "$symlink_repo_rc" -eq 2 ]]
grep -q '\[FAIL\] REPO-003' "$T/symlink-repo.out"
rm -f "$T/repos/linked.repo"
cat >"$T/bin/dnf" <<'EOF'
#!/usr/bin/env bash
exit 9
EOF
chmod +x "$T/bin/dnf"
set +e
sa_repo_doctor --section repo >"$T/backend-fail.out" 2>&1; backend_rc=$?
set -e
[[ "$backend_rc" -eq 2 ]]
grep -q '\[FAIL\] REPO-002' "$T/backend-fail.out"
cat >"$T/bin/dnf" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo 4.14.0; exit 0; }
exit 99
EOF
chmod +x "$T/bin/dnf"

# CLI exposes the read-only repository doctor without changing default doctor behavior.
cli_out=$(SA_OS_RELEASE_FILE="$T/os-release" SA_YUM_REPOS_DIR="$T/repos" "$ROOT/bin/stackalign" doctor --section repo)
[[ "$cli_out" == *"[PASS] REPO-001"* ]]
cli_json=$(SA_OS_RELEASE_FILE="$T/os-release" SA_YUM_REPOS_DIR="$T/repos" "$ROOT/bin/stackalign" doctor --section repo --json)
python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert len(d["checks"]) == 9' <<<"$cli_json"

echo "repo doctor tests: ok"
