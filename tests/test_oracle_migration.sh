#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
BIN="$ROOT/bin/stackalign-oracle"
mkdir -p "$T/etc" "$T/bin" "$T/repos"
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
export PATH="$T/bin:$PATH" FAKE_LOG="$T/log"
# Run in isolated root by substituting system paths via mount-independent test copy.
# The script supports test overrides only through the test fixture's sed copy.
cp "$BIN" "$T/stackalign-oracle"
sed -i "s|/etc/os-release|$T/os-release|g; s|/etc/yum.repos.d|$T/repos|g" "$T/stackalign-oracle"
printf '#!/bin/bash\nexit 0\n' > "$T/centos2ol.sh"
chmod +x "$T/centos2ol.sh"
HASH=$(/usr/bin/sha256sum "$T/centos2ol.sh" | awk '{print $1}')
out=$("$T/stackalign-oracle" convert plan --script "$T/centos2ol.sh" --sha256 "$HASH" --snapshot-id vm-snapshot)
[[ "$out" == *"PLAN ONLY"* && "$out" == *"CentOS 7.9.2009"* ]]
if "$T/stackalign-oracle" convert plan --script "$T/centos2ol.sh" --sha256 "$(printf '0%.0s' {1..64})" --snapshot-id vm-snapshot >/dev/null 2>&1; then exit 1; fi
if "$T/stackalign-oracle" convert plan --script "$T/centos2ol.sh" --sha256 "$HASH" >/dev/null 2>&1; then exit 1; fi
cat > "$T/os-release" <<'EOF'
ID=ol
VERSION_ID="8.10"
EOF
cat > "$T/repos/oracle.repo" <<'EOF'
[ol8_baseos_latest]
enabled=1
gpgcheck=1
EOF
out=$("$T/stackalign-oracle" update plan)
[[ "$out" == *"PLAN ONLY"* ]]
grep -q 'dnf --assumeno update' "$FAKE_LOG"
cat > "$T/repos/bad.repo" <<'EOF'
[untrusted]
enabled=1
gpgcheck=0
EOF
if "$T/stackalign-oracle" update plan >/dev/null 2>&1; then exit 1; fi
echo "oracle migration wrapper tests: PASS"
