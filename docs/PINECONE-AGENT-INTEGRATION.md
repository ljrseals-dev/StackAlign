# Pinecone Neural planning-sidecar integration

**Status: NOT ENABLED for StackAlign LLM planning. The current upstream main revision is not safe to deploy as a host-management agent.**

## Finding

The Pinecone Neural main branch inspected for this integration executes model-generated Python through eval/exec inside AgentHarness. Its separate Docker/gVisor sandbox helper is not wired into that execution path. This is not an acceptable execution boundary for an operational server-management product.

Hardening PRs may exist in the sidecar repository, but they must be reviewed against the exact deployed commit and tested independently. A PR being open or a helper existing in the repository is not evidence that the runtime is sandboxed.

## StackAlign behavior

- stackalign agent status remains a simple optional health probe.
- stackalign agent ask is disabled because it invokes the legacy agent endpoint and its current execution design has not passed the required hardening review.
- Use stackalign agent plan for the constrained OpenAI-compatible request planner described in LLM-PLANNER.md.
- StackAlign does not install, start, or supervise Pinecone Neural.

## Requirements before reconsidering the sidecar

1. Remove all model-generated source-code execution, including eval/exec and dynamic imports.
2. Use a closed registry of typed JSON tools with strict schemas and per-tool authorization.
3. Enforce request, response, token, time, memory, and output budgets.
4. Scope sessions and memory by authenticated principal; remove demo/default credentials.
5. Run as non-root with no host mounts, Docker socket, host network, or unnecessary capabilities.
6. Add tests proving unknown tools, unknown arguments, prompt injection, oversized output, timeout, and cross-user memory access are rejected.
7. Pin and review the exact image/source commit before deployment.

Until those conditions are verified, do not configure the sidecar as StackAlign's LLM provider.
