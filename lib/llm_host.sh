#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/llm_host.sh -- guarded local Ollama runtime discovery and model pulls.

_sa_llm_host_endpoint() {
  local host=${STACKALIGN_OLLAMA_HOST:-http://127.0.0.1:11434}
  [[ $host =~ ^http://(127\.0\.0\.1|localhost)(:[0-9]{1,5})?$ ]] || {
    echo "llm: Ollama endpoint must be loopback HTTP (127.0.0.1 or localhost)" >&2
    return 64
  }
  if [[ $host =~ :([0-9]{1,5})$ ]]; then
    local port=${BASH_REMATCH[1]}
    (( 10#$port >= 1 && 10#$port <= 65535 )) || { echo "llm: invalid Ollama port" >&2; return 64; }
  fi
  printf '%s\n' "$host"
}

_sa_llm_model_valid() {
  local model=$1
  [[ $model =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}(:[A-Za-z0-9._-]{1,64})?$ ]] &&
    [[ $model != *..* && $model != *//* && $model != */ ]]
}

sa_llm_host_status() {
  local host tmp rc
  host=$(_sa_llm_host_endpoint) || return $?
  if ! command -v ollama >/dev/null 2>&1; then
    echo "ollama: NOT INSTALLED"
    echo "endpoint: $host"
    echo "next: install Ollama from its official instructions and start its local service"
    return 2
  fi
  command -v curl >/dev/null 2>&1 || { echo "llm: curl is required" >&2; return 69; }
  command -v python3 >/dev/null 2>&1 || { echo "llm: python3 is required" >&2; return 69; }
  tmp=$(mktemp) || return 1
  chmod 600 "$tmp"
  if curl --silent --show-error --fail --connect-timeout 2 --max-time 5 \
      --max-filesize 1048576 --max-redirs 0 --output "$tmp" "$host/api/tags"; then
    if python3 - "$tmp" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        data = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
if not isinstance(data, dict) or not isinstance(data.get("models"), list):
    raise SystemExit(1)
for model in data["models"]:
    if not isinstance(model, dict) or not isinstance(model.get("name"), str):
        raise SystemExit(1)
print("runtime: Ollama API healthy")
for model in data["models"]:
    print("model: " + model["name"])
PY
    then rc=0
    else echo "llm: local endpoint returned an invalid Ollama model listing" >&2; rc=65
    fi
  else
    echo "runtime: Ollama endpoint unavailable at $host (service may be stopped)" >&2
    rc=2
  fi
  rm -f -- "$tmp"
  return "$rc"
}

sa_llm_host_models() {
  command -v ollama >/dev/null 2>&1 || { echo "llm: ollama is not installed" >&2; return 69; }
  ollama list
}

sa_llm_host_pull() {
  local model=$1 apply=${2:-0}
  _sa_llm_model_valid "$model" || { echo "llm: invalid model identifier" >&2; return 64; }
  command -v ollama >/dev/null 2>&1 || { echo "llm: ollama is not installed; no download attempted" >&2; return 69; }
  if [[ $apply != 1 ]]; then
    echo "plan: would run 'ollama pull $model'"
    echo "This downloads model data and consumes local disk space."
    echo "No network request or disk change was made; rerun with --apply to proceed."
    return 0
  fi
  echo "llm: pulling model '$model' via the installed Ollama CLI"
  ollama pull "$model"
}

sa_llm_host_help() {
  printf '%s\n' \
    'usage: stackalign llm <status|models|pull <model> [--apply]>' \
    '  status   inspect the loopback Ollama API (read-only)' \
    '  models   list models already present in Ollama' \
    '  pull     plan a model download; --apply explicitly downloads it' \
    'Set STACKALIGN_OLLAMA_HOST (default http://127.0.0.1:11434).' \
    'For agent plan, set STACKALIGN_LLM_BASE_URL=http://127.0.0.1:11434/v1'
}
