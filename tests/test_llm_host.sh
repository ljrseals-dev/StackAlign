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
if [[ $1 == list ]]; then
  [[ ${OLLAMA_HOST:-} == "127.0.0.1:11434" ]] || exit 10
  printf 'NAME ID SIZE\nlocal-model:latest abc 1GB\n'; exit 0
fi
if [[ $1 == pull ]]; then
  [[ ${OLLAMA_HOST:-} == "127.0.0.1:11434" ]] || exit 10
  printf '%s\n' "$*" > "$CAPTURE"; exit 0
fi
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

export STACKALIGN_OLLAMA_HOST=http://127.0.0.1:11434

export HOME="$T/home"
export STACKALIGN_LLM_CONFIG="$T/config/llm.env"
out=$(sa_llm_host_configure local-model:latest 0)
[[ $out == *"would create local planner config"* && ! -e $STACKALIGN_LLM_CONFIG ]]
echo "ok   local planner configuration defaults to plan"

sa_llm_host_configure local-model:latest 1 >/dev/null
[[ -f $STACKALIGN_LLM_CONFIG && ! -L $STACKALIGN_LLM_CONFIG ]]
[[ $(stat -c '%a' "$STACKALIGN_LLM_CONFIG") == 600 ]]
echo "ok   explicit configure writes a private config file"

unset STACKALIGN_LLM_BASE_URL STACKALIGN_LLM_MODEL
source "$ROOT/lib/llm.sh"
_sa_llm_load_config
[[ $STACKALIGN_LLM_BASE_URL == "http://127.0.0.1:11434/v1" ]]
[[ $STACKALIGN_LLM_MODEL == "local-model:latest" ]]
echo "ok   planner safely loads saved local endpoint and model"

# Existing directories must never have their permissions silently changed.
PUBLIC_DIR="$T/public-config"
mkdir -p "$PUBLIC_DIR"
chmod 755 "$PUBLIC_DIR"
if STACKALIGN_LLM_CONFIG="$PUBLIC_DIR/llm.env" sa_llm_host_configure another-model 1 >/dev/null 2>&1; then
  echo "FAIL: insecure existing config directory accepted" >&2; exit 1
fi
[[ $(stat -c '%a' "$PUBLIC_DIR") == 755 ]]
echo "ok   configure refuses broad directory permissions without changing them"

# Symlinked parent components must not redirect config creation.
ln -s "$T/config" "$T/config-link"
if STACKALIGN_LLM_CONFIG="$T/config-link/other.env" sa_llm_host_configure another-model 1 >/dev/null 2>&1; then
  echo "FAIL: symlinked config parent accepted" >&2; exit 1
fi
[[ ! -e "$T/config/other.env" ]]
echo "ok   configure rejects symlinked config parents"

# The planner must reject a config that is readable by other users.
chmod 644 "$STACKALIGN_LLM_CONFIG"
if _sa_llm_load_config >/dev/null 2>&1; then
  echo "FAIL: world-readable planner config accepted" >&2; exit 1
fi
chmod 600 "$STACKALIGN_LLM_CONFIG"
echo "ok   planner rejects insecure config-file permissions"

# Duplicate keys are ambiguous and must fail closed.
DUP_CONFIG="$T/duplicate.env"
printf '%s\n' 'STACKALIGN_LLM_BASE_URL=http://127.0.0.1:11434/v1' 'STACKALIGN_LLM_BASE_URL=http://127.0.0.1:11435/v1' 'STACKALIGN_LLM_MODEL=local-model:latest' > "$DUP_CONFIG"
chmod 600 "$DUP_CONFIG"
if STACKALIGN_LLM_CONFIG="$DUP_CONFIG" _sa_llm_load_config >/dev/null 2>&1; then
  echo "FAIL: duplicate planner config keys accepted" >&2; exit 1
fi
echo "ok   planner rejects duplicate configuration keys"

if sa_llm_host_configure another-model 1 >/dev/null 2>&1; then
  echo "FAIL: existing local config overwritten" >&2; exit 1
fi
echo "ok   existing local planner config is not overwritten"

CLI_HOME="$T/cli-home"
CLI_CONFIG="$CLI_HOME/.config/stackalign/llm.env"
out=$(HOME="$CLI_HOME" STACKALIGN_LLM_CONFIG="$CLI_CONFIG" bash "$ROOT/bin/stackalign" llm configure local-model:latest)
[[ $out == *"would create local planner config"* && ! -e $CLI_CONFIG ]]
echo "ok   CLI configure command is plan-only by default"

HOME="$CLI_HOME" STACKALIGN_LLM_CONFIG="$CLI_CONFIG" bash "$ROOT/bin/stackalign" llm configure local-model:latest --apply >/dev/null
[[ -f $CLI_CONFIG ]]
echo "ok   CLI configure applies the saved local model"

out=$(PATH="$T/bin:$PATH" bash "$ROOT/bin/stackalign" llm models)
[[ $out == *"local-model:latest"* ]]
echo "ok   CLI exposes local model inventory"
