# Pinecone Neural planning-sidecar integration

**Status: StackAlign CLI client implemented; sidecar deployment is manual and optional. No host automation is delegated to the model.**

## Why the harness is gated

The Pinecone Neural main branch inspected on 2026-11-18 had an unsafe model-generated Python execution path. PR #1 merged on 2026-11-20. A fresh check of current main SHA 30a2b5bf5b002b2454dc28f8f33ae633e5d9aa1c found that app/harness.py treats model output as data and dispatches only registered tools; the calculator uses a bounded AST evaluator. This source review is not a production deployment or provider-backed acceptance test.

The hardening work is a three-PR sequence: [PR #1](https://github.com/ljrseals-dev/pinecone-neural/pull/1) merged on 2026-11-20 and replaces model-generated Python with registered JSON tools while hardening identity/container defaults; [PR #2](https://github.com/ljrseals-dev/pinecone-neural/pull/2) remains open and fixes neural-memory contracts and adds history/resource budgets; [PR #3](https://github.com/ljrseals-dev/pinecone-neural/pull/3) remains open and makes chat calls asynchronous and serializes same-session transactions within one process. The latest cumulative PR #3 head 49d5dbdc713dc5fe3c779a5c5d8fe472c5530747 passed compileall and 34 tests in CI run [#44073253827](https://github.com/ljrseals-dev/pinecone-neural/actions/runs/44073253827). Earlier cumulative heads passed 10 tests (#1) and 30 tests (#2). These are credential-free tests; provider-backed end-to-end tests and deployment validation were not run. The currently merged mainline removes the reviewed Python execution path, but that does not establish production deployment safety. See [the pinned evidence ledger](SIDECAR-HARNESS-EVIDENCE-2026-11-18.md).

## Optional sidecar deployment

PR #1 is merged. Wait for PR #2 and PR #3 to be reviewed and merged, then verify the merged tree and pinned image before deploying this sidecar. The following is the intended manual deployment shape; it is not an installer executed by StackAlign.

1. Clone the Pinecone Neural repository and check out the reviewed, merged commit.
2. Copy .env.example to .env. Set PINECONE_API_KEY and OPENAI_API_KEY. Generate a unique API key with at least 32 random characters and set API_KEYS to key:user_id.
3. Restrict .env to owner read/write (chmod 600). Do not commit it or paste it into issue/PR text.
4. Build the container from the reviewed source.
5. Run it with no host filesystem mounts, no Docker socket, no host networking, no added capabilities, a read-only root filesystem, a small writable data volume, CPU/memory/PID limits, and no-new-privileges.
6. Publish the container port only on 127.0.0.1:8000. The service needs outbound HTTPS to its configured model and Pinecone providers; it does not need inbound public access.

Example container runtime policy (adapt the image tag to the reviewed build):

```bash
docker run -d --name pinecone-agent --restart unless-stopped \
  --publish 127.0.0.1:8000:8000 \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
  --volume pinecone-agent-data:/app/data \
  --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 128 --memory 2g --cpus 2 \
  --env-file /etc/stackalign/agent.env \
  pinecone-agent:reviewed
```

The container image in the PR #1 hardening branch runs as UID 10001. PR #3 session locks and the run semaphore are process-local; multi-worker/multi-host deployments still require sticky routing or a distributed lock. The runtime command does not mount host paths into the container. Keep provider credentials in the protected env file and rotate them independently.

## StackAlign commands

Check the local service:

```bash
stackalign agent status
```

Ask for a reviewable plan:

```bash
export STACKALIGN_AGENT_API_KEY='<the API key configured in the sidecar>'
stackalign agent ask "Review the current hosting and backup gaps"
```

The client sends the operator's question plus read-only output from StackAlign doctor and repository inventory. The API key is written to a mode-600 temporary header file and is not placed in curl's command-line arguments. Request/response temporary files are removed after use.

Default endpoint is http://127.0.0.1:8000. Remote HTTPS requires explicit STACKALIGN_AGENT_ALLOW_REMOTE=1. Plain remote HTTP, URL credentials, query strings, fragments, and untrusted redirect following are rejected.

## Authority boundary

- The model response is printed as advisory text and never executed by StackAlign.
- The sidecar has no host shell tool, root access, Docker socket, or host filesystem mount.
- The sidecar may use its own registered memory tools only.
- StackAlign host changes remain in the native CLI and require their own explicit apply gate and host checks.
- Never send API keys, passwords, private keys, database credentials, customer data, or sensitive logs in the prompt. The host snapshot is limited to doctor output and repository inventory; review it before enabling remote use.
- Pinecone/OpenAI provider traffic leaves the host. The operator must approve that data flow and provider account.

## Not yet automated

StackAlign does not yet install, build, upgrade, or supervise the Pinecone sidecar. That installer is intentionally deferred until the hardened upstream PR is merged and a reproducible, pinned container build has been validated. The current integration only connects to an already-running sidecar. It does not preserve a session_id between separate CLI invocations, so do not claim CLI-level conversational continuity from the sidecar's internal history tests. The sidecar's automated suite does not validate StackAlign's Nginx/PHP/TLS/database/backup/tenant host operations.
