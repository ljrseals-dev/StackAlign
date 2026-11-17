#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/bin/stackalign"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s' "$*" > "$CAPTURE_ARGS"
if [[ " $* " == *" /health "* ]]; then
  printf '{"status":"ok"}\n'
  exit 0
fi
header_file="" body_file="" output_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --header) [ $# -ge 2 ] || exit 2; [[ $2 == @* ]] && header_file=${2#@}; shift 2 ;;
    --data-binary) [ $# -ge 2 ] || exit 2; [[ $2 == @* ]] && body_file=${2#@}; shift 2 ;;
    --output) [ $# -ge 2 ] || exit 2; output_file=$2; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$header_file" ] && [ -n "$body_file" ] && [ -n "$output_file" ] || exit 2
cp "$header_file" "$CAPTURE_HEADER"
cp "$body_file" "$CAPTURE_BODY"
printf '{"session_id":"test-session","answer":"Plan only; no host changes."}\n' > "$output_file"
CURL
chmod +x "$T/bin/curl"
export PATH="$T/bin:$PATH"
export SA_ROOT="$ROOT"
export CAPTURE_ARGS="$T/args"
export CAPTURE_HEADER="$T/header"
export CAPTURE_BODY="$T/body"
pass=0 fail=0
ok(){ pass=$((pass+1)); echo "ok   - $1"; }
bad(){ fail=$((fail+1)); echo "FAIL - $1"; }

out=$(STACKALIGN_AGENT_URL=http://127.0.0.1:8000 bash "$CLI" agent status 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *'"status":"ok"'* ]]; } && ok "agent status uses local health endpoint" || bad "agent status"
out=$(STACKALIGN_AGENT_URL=http://example.com bash "$CLI" agent status 2>&1); rc=$?
{ [ "$rc" -eq 64 ] && [[ "$out" == *"loopback HTTP"* ]]; } && ok "plain HTTP remote endpoint rejected" || bad "remote HTTP rejection"
out=$(env -u STACKALIGN_AGENT_API_KEY STACKALIGN_AGENT_URL=http://127.0.0.1:8000 bash "$CLI" agent ask "review backups" 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && [[ "$out" == *"STACKALIGN_AGENT_API_KEY"* ]]; } && ok "agent ask fails closed without API key" || bad "missing key"
out=$(STACKALIGN_AGENT_URL=https://agent.example.com bash "$CLI" agent ask "review backups" 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && [[ "$out" == *"ALLOW_REMOTE"* ]]; } && ok "remote HTTPS requires explicit opt-in" || bad "remote HTTPS opt-in"
KEY=0123456789abcdef0123456789abcdef0123456789abcdef
out=$(STACKALIGN_AGENT_URL=http://127.0.0.1:8000 STACKALIGN_AGENT_API_KEY="$KEY" bash "$CLI" agent ask "review backup gaps" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [[ "$out" == *"Plan only; no host changes."* ]]; } && ok "agent ask returns advisory text" || bad "agent ask"
{ grep -q "$KEY" "$CAPTURE_HEADER" && ! grep -q "$KEY" "$CAPTURE_ARGS"; } && ok "API key is supplied through a private header file, not process arguments" || bad "API key process-list exposure"
{ grep -q "Operator request: review backup gaps" "$CAPTURE_BODY" && grep -q "Read-only host doctor output" "$CAPTURE_BODY" && grep -q "Read-only repository inventory" "$CAPTURE_BODY" && grep -q "reviewable plan only" "$CAPTURE_BODY"; } && ok "request includes read-only context and planning-only instruction" || bad "request context"
out=$(bash "$CLI" agent unknown 2>&1); rc=$?
[ "$rc" -eq 64 ] && ok "unknown agent subcommand rejected" || bad "unknown subcommand"

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
