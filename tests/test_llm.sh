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

unset STACKALIGN_LLM_API_KEY
if sa_llm_plan "check server" >/dev/null 2>&1; then
  echo "FAIL: missing provider key accepted" >&2; exit 1
fi
echo "ok   LLM plan refuses when provider key is missing"

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
