# StackAlign LLM request planner

**Status: implemented as an optional, read-only planner; provider calls and real-host behavior require operator setup and validation.**

## What it does

The planner accepts a natural-language request and asks an OpenAI-compatible chat-completions endpoint to return a small structured plan. StackAlign validates the response against its own schema and current capability allowlist before displaying it.

~~~bash
export STACKALIGN_LLM_API_KEY='your-provider-key'
stackalign agent plan "Check whether my web server is healthy"
~~~

Configuration:

| Variable | Default | Purpose |
|---|---|---|
| STACKALIGN_LLM_BASE_URL | https://api.openai.com/v1 | OpenAI-compatible API base URL |
| STACKALIGN_LLM_MODEL | gpt-4o-mini | Provider model identifier |
| STACKALIGN_LLM_API_KEY | unset | Provider API key; required |

A local OpenAI-compatible endpoint may use HTTP only when the hostname is localhost or 127.0.0.1. Remote endpoints must use HTTPS. URL credentials, query strings, fragments, redirects, and malformed ports are rejected. The request and API key are held in a mode-700 temporary directory with mode-600 files and removed when the command exits. The key is not put in curl's command-line arguments or printed.

## Authority and privacy boundary

- The planner sends only the operator's text request and a fixed StackAlign system prompt. It does not collect or transmit doctor output, repository inventory, hostnames, configuration files, service state, customer data, or secrets.
- The LLM response is untrusted input. It is parsed as JSON and validated by scripts/validate_llm_plan.py.
- The only task type currently accepted is health_check, and it is only a proposed task record. It does not run a health check or change a host.
- Unsupported workflows are listed as unsupported requests rather than converted into shell commands or executable actions.
- No model output is passed to a shell, SQL interpreter, package manager, Docker, or filesystem mutation function.
- The planner does not automatically create task records, schedule work, retry tasks, or apply changes.
- Provider traffic leaves the machine. The operator chooses and configures the provider and is responsible for its account, retention, and data-processing terms.

## Current capability limit

Website deployment, database provisioning, backups, restores, migrations, TLS issuance, firewall management, user lifecycle, and package changes are not planner-executable workflows. They must remain unsupported until deterministic StackAlign implementations, tests, preflight checks, rollback behavior, and explicit confirmation gates exist.

## Pinecone Neural sidecar

The existing Pinecone Neural main branch inspected for this integration uses model-generated Python with eval/exec in its agent loop. Its separate Docker/gVisor helper is not wired into that execution path. StackAlign therefore does not use that service as its LLM provider and the legacy stackalign agent ask command is disabled. The optional stackalign agent status health probe remains available. See the sidecar review (PINECONE-AGENT-INTEGRATION.md).

## Testing

tests/test_llm.sh uses a fake curl executable and canned provider responses. It tests request construction and response validation without making a network request or sending data to a provider. CI does not validate a live provider account or model response.
