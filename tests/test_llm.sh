#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export SA_ROOT="$ROOT" STACKALIGN_LLM_API_KEY="test-provider-key-123456789"
export STACKALIGN_LLM_BASE_URL="http://127.0.0.1:18080/v1"
export STACKALIGN_LLM_MODEL="test-model"
export LLM_TEST_RESPONSE="$TMP/response.json"
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
out= data= headers= url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) out=$2; shift 2 ;;
    --data-binary) data=$2; shift 2 ;;
    --header) headers=$2; shift 2 ;;
    http://*|https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
[[ $url == "http://127.0.0.1:18080/v1/chat/completions" ]]
[[ $headers == @* && -f ${headers#@} ]]
[[ $data == @* && -f ${data#@} ]]
python3 - "${data#@}" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["model"] == "test-model"
assert payload["response_format"] == {"type":"json_object"}
assert len(payload["messages"]) == 2
assert "health_check" in payload["messages"][0]["content"]
PY
cat "$LLM_TEST_RESPONSE" > "$out"
MOCK
chmod 700 "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
source "$ROOT/lib/llm.sh"

cat > "$LLM_TEST_RESPONSE" <<'JSON'
{"choices":[{"message":{"content":"{\"summary\":\"A read-only health review is appropriate.\",\"tasks\":[{\"type\":\"health_check\",\"description\":\"Inspect service and configuration health.\"}],\"questions\":[],\"warnings\":[\"No host state was inspected.\"],\"unsupported_requests\":[]}"}}]}
JSON
cp "$LLM_TEST_RESPONSE" "$TMP/valid-response.json"
OUT=$(sa_llm_plan "Please check whether my server is healthy")
[[ $OUT == *'"type": "health_check"'* ]]
[[ $OUT == *'"No host state was inspected."'* ]]
echo "ok   LLM plan accepts a valid constrained health-check proposal"

cat > "$LLM_TEST_RESPONSE" <<'JSON'
{"choices":[{"message":{"content":"{\"summary\":\"Run an arbitrary command.\",\"tasks\":[{\"type\":\"shell_command\",\"description\":\"run id\"}],\"questions\":[],\"warnings\":[],\"unsupported_requests\":[]}"}}]}
JSON
if sa_llm_plan "run id" >/dev/null 2>&1; then
  echo "FAIL: unregistered task type accepted" >&2; exit 1
fi
echo "ok   LLM plan rejects arbitrary execution task types"

export STACKALIGN_LLM_BASE_URL="https://api.example.com/v1"
unset STACKALIGN_LLM_API_KEY
if sa_llm_plan "check server" >/dev/null 2>&1; then
  echo "FAIL: missing provider key accepted" >&2; exit 1
fi
echo "ok   LLM plan requires a key for remote HTTPS providers"

export STACKALIGN_LLM_API_KEY="test-provider-key-123456789"
export STACKALIGN_LLM_BASE_URL="http://example.com/v1"
if sa_llm_plan "check server" >/dev/null 2>&1; then
  echo "FAIL: remote plaintext HTTP endpoint accepted" >&2; exit 1
fi
echo "ok   LLM plan rejects remote plaintext HTTP"

export STACKALIGN_LLM_BASE_URL="http://127.0.0.1:18080/v1"
cat > "$LLM_TEST_RESPONSE" <<'JSON'
{"choices":[{"message":{"content":"not json"}}]}
JSON
if sa_llm_plan "check server" >/dev/null 2>&1; then
  echo "FAIL: malformed model output accepted" >&2; exit 1
fi
echo "ok   LLM plan rejects malformed model output"

# A response containing tool calls must never be treated as a normal plan.
cat > "$LLM_TEST_RESPONSE" <<'JSON'
{"choices":[{"message":{"role":"assistant","content":"{\"summary\":\"A safe plan.\",\"tasks\":[],\"questions\":[],\"warnings\":[],\"unsupported_requests\":[]}","tool_calls":[{"type":"function","function":{"name":"dangerous_action","arguments":"{}"}}]},"finish_reason":"stop"}]}
JSON
if sa_llm_plan "check server" >/dev/null 2>&1; then
  echo "FAIL: tool-call response accepted" >&2; exit 1
fi
echo "ok   LLM plan rejects tool-call responses even when content is valid"

# Duplicate JSON keys are ambiguous and must not be normalized by last-key-wins parsing.
printf '%s\\n' '{"summary":"first","summary":"second","tasks":[],"questions":[],"warnings":[],"unsupported_requests":[]}' > "$LLM_TEST_RESPONSE"
if python3 "$ROOT/scripts/validate_llm_plan.py" "$LLM_TEST_RESPONSE" >/dev/null 2>&1; then
  echo "FAIL: duplicate JSON keys accepted" >&2; exit 1
fi
echo "ok   plan validator rejects duplicate JSON keys"

unset STACKALIGN_LLM_API_KEY
cp "$TMP/valid-response.json" "$LLM_TEST_RESPONSE"
OUT=$(sa_llm_plan "Explain the local health-check capability")
[[ $OUT == *'"type": "health_check"'* ]]
echo "ok   local OpenAI-compatible endpoint works without an API key"
