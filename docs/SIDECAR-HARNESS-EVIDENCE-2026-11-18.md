# Pinecone Neural sidecar harness evidence

**Evidence refresh:** 2026-11-18 UTC  
**StackAlign target:** ljrseals-dev/StackAlign, audit branch audit/prompt-coverage-sidecar-2026-11-18  
**Sidecar repository:** ljrseals-dev/pinecone-neural  
**Purpose:** record what the sidecar's automated harness can and cannot establish for StackAlign's master engineering prompt.

## Executive result

The sidecar provides a useful, credential-free regression harness for its own agent runtime, memory pipeline, API resource controls and session behavior. The latest inspected cumulative branch, PR #3 head 49d5dbdc713dc5fe3c779a5c5d8fe472c5530747, passed Python compilation and 34 pytest tests in GitHub Actions run [#44073253827](https://github.com/ljrseals-dev/pinecone-neural/actions/runs/44073253827).

This does not mean StackAlign's A–O hosting capabilities have been tested by the sidecar, that a live sidecar was contacted, or that provider-backed behavior works. The three sidecar PRs are stacked and remain open/unmerged. CI uses placeholder provider credentials explicitly marked unused.

## Pinned source chain and CI evidence

| Change | Head SHA | Base | GitHub Actions | Result |
|---|---|---|---|---|
| [PR #1 — Harden agent tools and session isolation](https://github.com/ljrseals-dev/pinecone-neural/pull/1) | a57e6e1c5cfea2231a9562e3f133ea961e0eb9fb | main 8260ee84fc6deb96aeebe46079d47948a30cd84d | [#44035274780](https://github.com/ljrseals-dev/pinecone-neural/actions/runs/44035274780) | compileall + 10 tests passed |
| [PR #2 — Fix neural memory pipeline and enforce runtime budgets](https://github.com/ljrseals-dev/pinecone-neural/pull/2) | 78334bac420d778ef30fe5c3b4f0ffaf6b5f3702 | PR #1 head | [#44039697690](https://github.com/ljrseals-dev/pinecone-neural/actions/runs/44039697690) | compileall + 30 tests passed |
| [PR #3 — Avoid blocking API loop and serialize session updates](https://github.com/ljrseals-dev/pinecone-neural/pull/3) | 49d5dbdc713dc5fe3c779a5c5d8fe472c5530747 | PR #2 head | [#44073253827](https://github.com/ljrseals-dev/pinecone-neural/actions/runs/44073253827) | compileall + 34 tests passed |

All three PRs were open and unmerged at this evidence refresh. Test counts are cumulative snapshots, not additive: do not report 74 unique tests. The latest single run is 34 passed.

## What the harness exercises

### PR #1 — tool and identity boundary

- Model-generated Python execution is disabled; model output is expected to be a JSON tool call or final answer.
- Tool names are registered/allow-listed; required and unknown fields, primitive types, lengths and numeric bounds are checked.
- Tool execution has timeout and output-size controls; calculator arithmetic uses a bounded AST evaluator rather than eval.
- API keys fail closed, enforce minimum length and safe user identifiers, and are compared with constant-time comparison.
- Pinecone namespaces and session identifiers are scoped to the authenticated user.
- Demo keys are removed; the container runs as UID 10001; local runner defaults to loopback.
- Tests cover Python execution disabled, allowlist/schema behavior, calculator bounds, duplicate tool registration and API-key parsing.

### PR #2 — memory correctness and resource limits

- Corrects neural memory integration contracts and recall ranking across GNN diffusion, synaptic association and utility scoring.
- Adds coverage for negative/isolated cosine behavior, deterministic cold-start utility, memory metadata protection, idempotent sidecar repair, soft-delete revival and retention cleanup.
- Replays authenticated conversation history and bounds stored history and Pinecone namespace length.
- Bounds embedding inputs and index-readiness waits; adds provider and Redis timeouts/retry bounds.
- Enforces tool timeout/output limits, per-run token and estimated-cost budgets, including embedding accounting.
- Loads Redis/neural storage paths from validated settings; closes Redis at shutdown.
- Uses explicit CORS origin allowlists and loopback defaults.
- The cost ceiling is an estimate using configurable per-million-token rates. It is not provider billing truth and excludes Pinecone read/write units, Redis and host costs.
- CI run #44039697690 passed 30 tests on this PR head.

### PR #3 — asynchronous API and concurrency

- Uses AsyncOpenAI for chat completions so provider latency does not block the FastAPI event loop.
- Serializes a same-session read/run/write transaction and session deletion within one process.
- Allows independent sessions to progress concurrently.
- Bounds in-flight agent runs per process and bounds retained conversation history.
- Tests event-loop responsiveness, same-session serialization, independent-session concurrency, cancellation cleanup and lock reclamation.
- Explicit limitation: locks and semaphore are process-local. Multi-worker/multi-host deployments need sticky routing or a distributed lock.
- CI run #44073253827 passed 34 tests on this cumulative PR head.

## What this does not establish

- No provider-backed OpenAI or Pinecone end-to-end tests were run.
- No production image deployment, container runtime policy, secrets injection, provider egress or host integration was validated.
- No StackAlign host operation is executed by the model; the sidecar is not an installer, root daemon or orchestration authority.
- StackAlign lib/agent.sh sends read-only doctor/repository output and prints the answer. Its tests use fake curl, not a live API.
- The current StackAlign client does not pass/persist a session_id across CLI invocations; do not infer CLI-level conversation continuity from the sidecar's internal history tests.
- Sidecar tests validate sidecar code paths, not StackAlign prompt categories A–O such as Nginx/PHP/TLS/database lifecycle, backups/restores, tenant isolation or host recovery.
- Sidecar main SHA 8260ee84fc6deb96aeebe46079d47948a30cd84d still contains the unsafe model-generated Python execution path identified in the original review. The hardening chain is not yet merged into main.

## Safe use for StackAlign

1. Treat sidecar output as advisory and untrusted.
2. Send only deliberately sanitized, non-sensitive repository/doctor data after an operator approves provider egress.
3. Require path, line, commit SHA and test evidence for each finding.
4. Reproduce each claim locally in StackAlign's own tests/CI before accepting it.
5. Keep all apply/privileged operations in StackAlign's native approval-gated workflows.
