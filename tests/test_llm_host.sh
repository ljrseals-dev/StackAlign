#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
export CAPTURE="$T/pull-args"
cat > "$T/bin/ollama" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == list ]]; then printf 'NAME ID SIZE\nlocal-model:latest abc 1GB\n'; exit 0; fi
if [[ $1 == pull ]]; then printf '%s\n' "$*" > "$CAPTURE"; exit 0; fi
exit 64
MOCK
cat > "$T/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
out=
while [ "$#" -gt 0 ]; do
  case "$1" in --output) out=$2; shift 2 ;; *) shift ;; esac
done
printf '{"models":[{"name":"local-model:latest"}]}\n' > "$out"
MOCK
chmod 700 "$T/bin/"*
export PATH="$T/bin:$PATH"
source "$ROOT/lib/llm_host.sh"

export STACKALIGN_OLLAMA_HOST=http://127.0.0.1:11434
out=$(sa_llm_host_status)
[[ $out == *"runtime: Ollama API healthy"* && $out == *"local-model:latest"* ]]
echo "ok   local Ollama endpoint health and model inventory"

out=$(sa_llm_host_pull local-model:latest 0)
[[ $out == *"would run 'ollama pull local-model:latest'"* ]]
[[ ! -e $CAPTURE ]]
echo "ok   model pull defaults to plan and makes no network request"

sa_llm_host_pull local-model:latest 1 >/dev/null
[[ $(cat "$CAPTURE") == "pull local-model:latest" ]]
echo "ok   model pull executes only with explicit apply"

if sa_llm_host_pull '../escape' 0 >/dev/null 2>&1; then
  echo "FAIL: unsafe model identifier accepted" >&2; exit 1
fi
echo "ok   unsafe model identifiers rejected"

export STACKALIGN_OLLAMA_HOST=http://0.0.0.0:11434
if sa_llm_host_status >/dev/null 2>&1; then
  echo "FAIL: non-loopback Ollama endpoint accepted" >&2; exit 1
fi
echo "ok   non-loopback Ollama management endpoint rejected"
