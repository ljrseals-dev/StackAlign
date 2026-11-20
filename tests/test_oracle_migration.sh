#!/usr/bin/env bash
# Copyright (c) 2026 Lewis James Seals Jr.
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Repository: https://github.com/ljrseals-dev/StackAlign
set -Eeuo pipefail
trap 'printf "oracle test failed at line %s (rc=%s)\n" "$LINENO" "$?" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
BIN="$ROOT/bin/stackalign-oracle"
mkdir -p "$T/bin" "$T/repos"
cat > "$T/os-release" <<'EOF'
ID=centos
VERSION_ID="7.9.2009"
EOF
cat > "$T/bin/id" <<'EOF'
#!/usr/bin/env bash
echo 0
EOF
cat > "$T/bin/uname" <<'EOF'
#!/usr/bin/env bash
echo x86_64
EOF
cat > "$T/bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/sha256sum "$@"
EOF
cat > "$T/bin/yum" <<'EOF'
#!/usr/bin/env bash
printf 'yum %s\n' "$*" >> "$FAKE_LOG"
exit 0
EOF
cat > "$T/bin/dnf" <<'EOF'
#!/usr/bin/env bash
printf 'dnf %s\n' "$*" >> "$FAKE_LOG"
exit 0
EOF
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" FAKE_LOG="$T/log" TEST_OS_RELEASE="$T/os-release"
# Isolate host paths by substituting them in a private test copy.
cp "$BIN" "$T/stackalign-oracle"
sed -i "s|/etc/os-release|$T/os-release|g; s|/etc/yum.repos.d|$T/repos|g" "$T/stackalign-oracle"
cat > "$T/centos2ol.sh" <<'EOF'
#!/usr/bin/env bash
printf 'ID=ol\nVERSION_ID="7.9"\n' > "$TEST_OS_RELEASE"
EOF
chmod +x "$T/centos2ol.sh"
HASH=$(/usr/bin/sha256sum "$T/centos2ol.sh" | awk '{print $1}')

# CentOS 7 conversion: plan, checksum refusal, missing snapshot refusal,
# explicit confirmation, staged execution, and post-conversion OS check.
out=$(bash "$T/stackalign-oracle" convert plan --script "$T/centos2ol.sh" --sha256 "$HASH" --snapshot-id vm-snapshot)
[[ "$out" == *"PLAN ONLY"* && "$out" == *"centos 7.9.2009"* ]]
if bash "$T/stackalign-oracle" convert plan --script "$T/centos2ol.sh" --sha256 "$(printf '0%.0s' {1..64})" --snapshot-id vm-snapshot >/dev/null 2>&1; then exit 1; fi
if bash "$T/stackalign-oracle" convert plan --script "$T/centos2ol.sh" --sha256 "$HASH" >/dev/null 2>&1; then exit 1; fi
if bash "$T/stackalign-oracle" convert apply --script "$T/centos2ol.sh" --sha256 "$HASH" --snapshot-id vm-snapshot --apply >/dev/null 2>&1; then exit 1; fi
SA_ORACLE_CONFIRM=CONVERT-CENTOS-TO-ORACLE-LINUX bash "$T/stackalign-oracle" convert apply --script "$T/centos2ol.sh" --sha256 "$HASH" --snapshot-id vm-snapshot --apply >/dev/null
grep -q '^ID=ol$' "$T/os-release"

# Oracle Linux 8 uses only explicitly GPG-checked Oracle public repositories
# and DNF. Update apply requires the separate confirmation phrase.
cat > "$T/os-release" <<'EOF'
ID=ol
VERSION_ID="8.10"
EOF
cat > "$T/repos/oracle.repo" <<'EOF'
[ol8_baseos_latest]
enabled=1
gpgcheck=1
baseurl=https://yum.oracle.com/repo/OracleLinux/OL8/baseos/latest/x86_64/
EOF
out=$(bash "$T/stackalign-oracle" update plan)
[[ "$out" == *"PLAN ONLY"* ]]
grep -q 'dnf --assumeno update' "$FAKE_LOG"
if bash "$T/stackalign-oracle" update apply --apply >/dev/null 2>&1; then exit 1; fi
SA_ORACLE_CONFIRM=APPLY-ORACLE-LINUX-UPDATES bash "$T/stackalign-oracle" update apply --apply
grep -q 'dnf -y update' "$FAKE_LOG"

# Oracle Linux 7 must use yum, not dnf.
cat > "$T/os-release" <<'EOF'
ID=ol
VERSION_ID="7.9"
EOF
rm -f "$T/repos/"*.repo
cat > "$T/repos/ol7.repo" <<'EOF'
[ol7_latest]
enabled=1
gpgcheck=1
baseurl=https://yum.oracle.com/repo/OracleLinux/OL7/latest/x86_64/
EOF
bash "$T/stackalign-oracle" update plan >/dev/null
grep -q 'yum --assumeno update' "$FAKE_LOG"

# A non-Oracle or unsigned enabled repository must be rejected.
cat > "$T/repos/bad.repo" <<'EOF'
[untrusted]
enabled=1
gpgcheck=0
baseurl=https://mirror.example.invalid/repo/
EOF
if bash "$T/stackalign-oracle" update plan >/dev/null 2>&1; then exit 1; fi
echo "oracle migration wrapper tests: PASS"
