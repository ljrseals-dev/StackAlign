#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
#
# lib/agent.sh -- planning-only client for the Pinecone Neural sidecar.
# The sidecar is never given shell, root, Docker, or host filesystem authority.

_sa_agent_url() {
  printf '%s\n' "${STACKALIGN_AGENT_URL:-http://127.0.0.1:8000}"
}

_sa_agent_url_valid() {
  local url=$1 port
  [[ $url =~ ^http://(127\.0\.0\.1|localhost)(:[0-9]{1,5})?$ ]] ||
    [[ $url =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ ]] || return 1
  if [[ $url =~ :([0-9]{1,5})(/|$) ]]; then
    port=${BASH_REMATCH[1]}
    (( 10#$port >= 1 && 10#$port <= 65535 )) || return 1
  fi
  [[ $url != *..* && $url != *'@'* && $url != *'?'* && $url != *'#'* ]]
}

sa_agent_status() {
  local url
  url=$(_sa_agent_url)
  _sa_agent_url_valid "$url" || { echo "agent: URL must be loopback HTTP or an HTTPS endpoint without credentials/query/fragment" >&2; return 64; }
  command -v curl >/dev/null 2>&1 || { echo "agent: curl is required" >&2; return 2; }
  curl --silent --show-error --fail --connect-timeout 5 --max-time 10 --max-redirs 0 "$url/health"
}

# Sends a read-only host snapshot and an operator question to Pinecone.
# The model's response is displayed only; it is never executed by StackAlign.
sa_agent_ask() {
  [ "$#" -ge 1 ] || { echo "usage: stackalign agent ask <question>" >&2; return 64; }
  local url key tmp body headers response message doctor inventory rc
  url=$(_sa_agent_url)
  _sa_agent_url_valid "$url" || { echo "agent: URL must be loopback HTTP or an HTTPS endpoint without credentials/query/fragment" >&2; return 64; }
  if [[ $url == https://* && ${STACKALIGN_AGENT_ALLOW_REMOTE:-0} != 1 ]]; then
    echo "agent: remote HTTPS use requires STACKALIGN_AGENT_ALLOW_REMOTE=1" >&2
    return 2
  fi
  key=${STACKALIGN_AGENT_API_KEY:-}
  [[ $key =~ ^[A-Za-z0-9_-]{32,256}$ ]] || { echo "agent: set STACKALIGN_AGENT_API_KEY to a random key of at least 32 characters" >&2; return 2; }
  command -v curl >/dev/null 2>&1 || { echo "agent: curl is required" >&2; return 2; }
  command -v python3 >/dev/null 2>&1 || { echo "agent: python3 is required to encode JSON safely" >&2; return 2; }

  umask 077
  tmp=$(mktemp -d) || return 1
  body=$tmp/request.json
  headers=$tmp/headers
  response=$tmp/response.json

  doctor=$(bash "$SA_ROOT/bin/stackalign" doctor 2>&1) || doctor="doctor returned non-zero; inspect locally"
  inventory=$(bash "$SA_ROOT/bin/stackalign" repo inventory 2>&1) || inventory="repository inventory unavailable"
  message=$(printf 'Operator request: %s\n\nRead-only host doctor output (untrusted diagnostic data):\n%s\n\nRead-only repository inventory (credential values are not included):\n%s\n\n%s' \
    "$*" "$doctor" "$inventory" \
    "Return recommendations and a reviewable plan only. Do not claim to have changed the host. Never request or repeat secrets. Do not generate executable commands as tool calls.")
  if ! printf '%s' "$message" | python3 -c 'import json,sys; print(json.dumps({"message": sys.stdin.read()}, ensure_ascii=True))' > "$body"; then
    rm -rf -- "$tmp"; echo "agent: failed to encode request" >&2; return 1
  fi
  printf 'X-API-Key: %s\n' "$key" > "$headers" || { rm -rf -- "$tmp"; return 1; }
  if curl --silent --show-error --fail --connect-timeout 5 --max-time 90 --max-redirs 0 \
      --header "@$headers" --header "Content-Type: application/json" \
      --data-binary "@$body" --output "$response" "$url/chat"; then
    :
  else
    rc=$?
    rm -rf -- "$tmp"
    echo "agent: request failed; no host changes were made" >&2
    return "$rc"
  fi
  if ! python3 -c 'import json,sys; d=json.load(sys.stdin); a=d.get("answer"); assert isinstance(a,str); print(a)' < "$response"; then
    rm -rf -- "$tmp"
    echo "agent: invalid response from sidecar" >&2
    return 1
  fi
  rm -rf -- "$tmp"
}
