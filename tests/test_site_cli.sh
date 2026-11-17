#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# tests/test_site_cli.sh -- site command routing and fail-closed lifecycle.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/nginx" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = -t ] && exit 0
exit 64
EOF
cat > "$TMP/bin/httpd" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = -t ] && exit 0
exit 64
EOF
chmod 700 "$TMP/bin/"*
PATH="$TMP/bin:$PATH" bash "$ROOT/bin/stackalign" site doctor nginx | grep -q 'nginx_config: valid'
set +e
PATH="$TMP/bin:$PATH" bash "$ROOT/bin/stackalign" site add example.com >"$TMP/out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -q 'BLOCKED' "$TMP/out"
echo 'site CLI tests: PASS'
