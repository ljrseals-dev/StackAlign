#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# lib/llm.sh -- provider-neutral, read-only LLM planner client.

_sa_llm_url_valid() {
  local url=$1 port
  [[ $url =~ ^http://(127\\.0\\.0\\.1|localhost)(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ ]] ||
    [[ $url =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ ]] || return 1
  if [[ $url =~ :([0-9]{1,5})(/|$) ]]; then
    port=${BASH_REMATCH[1]}
    (( 10#$port >= 1 && 10#$port <= 65535 )) || return 1
  fi
  [[ $url != *..* && $url != *'@'* && $url != *'?'* && $url != *'#'* ]]
}

_sa_llm_load_config() {
  local config line key value owner mode canonical
  local config_url="" config_model="" lines=0 seen_url=0 seen_model=0
  config=${STACKALIGN_LLM_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/stackalign/llm.env}
  [[ -e $config || -L $config ]] || return 0
  [[ -f $config && ! -L $config ]] || {
    echo "agent: local LLM config must be a regular non-symlink file" >&2
    return 2
  }
  canonical=$(realpath -e -- "$config") || return 2
  [[ $canonical == "$config" ]] || {
    echo "agent: local LLM config path must not contain symlinked or non-canonical components" >&2
    return 2
  }
  owner=$(stat -c '%u' -- "$config") || return 2
  mode=$(stat -c '%a' -- "$config") || return 2
  [[ $owner == "$(id -u)" ]] || {
    echo "agent: local LLM config must be owned by the current user" >&2
    return 2
  }
  (( (8#$mode & 077) == 0 )) || {
    echo "agent: local LLM config permissions are too broad; require mode 600 or stricter" >&2
    return 2
  }

  while IFS= read -r line || [[ -n $line ]]; do
    ((lines += 1))
    (( lines <= 2 )) || { echo "agent: local LLM config has too many entries" >&2; return 2; }
    [[ $line == *=* && $line != *$'\x0d'* ]] || {
      echo "agent: malformed local LLM config" >&2
      return 2
    }
    key=${line%%=*}
    value=${line#*=}
    [[ -n $value ]] || { echo "agent: empty value in local LLM config" >&2; return 2; }
    case "$key" in
      STACKALIGN_LLM_BASE_URL)
        (( seen_url == 0 )) || { echo "agent: duplicate base URL in local LLM config" >&2; return 2; }
        seen_url=1; config_url=$value ;;
      STACKALIGN_LLM_MODEL)
        (( seen_model == 0 )) || { echo "agent: duplicate model in local LLM config" >&2; return 2; }
        seen_model=1; config_model=$value ;;
      *) echo "agent: unsupported key in local LLM config: $key" >&2; return 2 ;;
    esac
  done < "$config"
  (( seen_url == 1 && seen_model == 1 && lines == 2 )) || {
    echo "agent: local LLM config must contain exactly one base URL and one model" >&2
    return 2
  }
  _sa_llm_url_valid "$config_url" || {
    echo "agent: invalid base URL in local LLM config" >&2
    return 2
  }
  [[ $config_model =~ ^[A-Za-z0-9][A-Za-z0-9._:/+-]{0,127}$ ]] || {
    echo "agent: invalid model in local LLM config" >&2
    return 2
  }
  [[ -n ${STACKALIGN_LLM_BASE_URL:-} ]] || export STACKALIGN_LLM_BASE_URL=$config_url
  [[ -n ${STACKALIGN_LLM_MODEL:-} ]] || export STACKALIGN_LLM_MODEL=$config_model
}

sa_llm_plan() {
  [ "$#" -ge 1 ] || { echo "usage: stackalign agent plan <request>" >&2; return 64; }
  _sa_llm_load_config || return $?
  local request="$*" base_url model key
  (( ${#request} <= 4000 )) || { echo "agent: request exceeds 4000 characters" >&2; return 64; }
  base_url=${STACKALIGN_LLM_BASE_URL:-https://api.openai.com/v1}
  model=${STACKALIGN_LLM_MODEL:-gpt-4o-mini}
  key=${STACKALIGN_LLM_API_KEY:-}
  _sa_llm_url_valid "$base_url" || { echo "agent: LLM base URL must be loopback HTTP or a valid HTTPS URL without credentials/query/fragment" >&2; return 64; }
  [[ $model =~ ^[A-Za-z0-9][A-Za-z0-9._:/+-]{0,127}$ ]] || { echo "agent: invalid LLM model name" >&2; return 64; }
  if [[ $base_url == https://* ]]; then
    [[ $key =~ ^[A-Za-z0-9._-]{16,512}$ ]] || { echo "agent: set STACKALIGN_LLM_API_KEY for remote HTTPS providers" >&2; return 2; }
  else
    [[ -z $key || $key =~ ^[A-Za-z0-9._-]{16,512}$ ]] || { echo "agent: invalid local-provider API key" >&2; return 2; }
  fi
  command -v curl >/dev/null 2>&1 || { echo "agent: curl is required" >&2; return 69; }
  command -v python3 >/dev/null 2>&1 || { echo "agent: python3 is required" >&2; return 69; }
  base_url=$(printf '%s' "$base_url" | sed 's:/*$::')

  (
    umask 077
    local tmp body headers response rc
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf -- "$tmp"' EXIT
    body=$tmp/request.json
    headers=$tmp/headers
    response=$tmp/response.json
    python3 - "$body" "$model" "$request" <<'PY'
import json
import sys

path, model, request = sys.argv[1:4]
system = """You are StackAlign's request-planning assistant.
Return one JSON object only, with exactly these keys:
summary (string), tasks (array), questions (array of strings),
warnings (array of strings), unsupported_requests (array of strings).
A task object has exactly: type (string), description (string).
The ONLY currently available task type is health_check.
Create a health_check task only when the request genuinely asks for a read-only
server health inspection. For deployment, database provisioning, backup,
restore, migration, package changes, firewall changes, TLS issuance, account
changes, or any other operation, do not invent a task. Put the requested work
in unsupported_requests and explain the missing implementation in warnings.
Never emit shell commands, code, SQL, URLs to execute, credentials, or tool calls.
Do not claim a task has run. Do not infer host state: no host data is provided.
Limit tasks, questions, warnings, and unsupported_requests to five entries each.
Descriptions and strings must be concise and factual."""
payload = {
    "model": model,
    "temperature": 0.1,
    "max_tokens": 1200,
    "response_format": {"type": "json_object"},
    "messages": [
        {"role": "system", "content": system},
        {"role": "user", "content": request},
    ],
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=True)
PY
    if [[ -n $key ]]; then
      printf 'Authorization: Bearer %s\\nContent-Type: application/json\\n' "$key" > "$headers" || exit 1
    else
      printf 'Content-Type: application/json\\n' > "$headers" || exit 1
    fi
    if curl --silent --show-error --fail --connect-timeout 5 --max-time 60 \\
        --max-filesize 1048576 --max-redirs 0 \\
        --header "@$headers" --data-binary "@$body" \\
        --output "$response" "$base_url/chat/completions"; then
      :
    else
      rc=$?
      echo "agent: LLM request failed (curl exit $rc); no host actions were attempted" >&2
      exit 1
    fi
    python3 "$SA_ROOT/scripts/validate_llm_plan.py" "$response"
  )
}
