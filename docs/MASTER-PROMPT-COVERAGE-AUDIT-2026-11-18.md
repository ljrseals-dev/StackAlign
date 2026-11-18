# Master Engineering Prompt Coverage Audit

**Inspection date:** 2026-11-18 UTC  
**StackAlign repository:** https://github.com/ljrseals-dev/StackAlign  
**StackAlign branch / commit inspected:** `main` / `ca069223d7ba5ac071d3198508d47f172ad49009`  
**Centmin Mod comparison:** `master` / `4e7aec8585c6ad169773d1a77df17f560e4e0d71`; relevant beta baseline previously pinned in the existing assessment as `141.00beta01` / `1d1146eb17b82b246a15e49a4addca92f8b748d4`  
**Sidecar:** https://github.com/ljrseals-dev/pinecone-neural, `main` / `8260ee84fc6deb96aeebe46079d47948a30cd84d`  
**Sidecar hardening PR:** https://github.com/ljrseals-dev/pinecone-neural/pull/1 — open, not merged, at inspection.

## Executive result

This is a prompt-coverage triage against all fifteen capability groups (A–O), not a claim that every individual acceptance criterion has been implemented or integration-tested. The current StackAlign tree contains a substantial shell-based foundation and many read-only planners, but several core hosting lifecycle operations remain deliberately blocked or incomplete. The largest verified maturity gaps remain end-to-end TLS lifecycle, tenant/site isolation and lifecycle, database user/grant lifecycle, schema-validated persistent configuration, package upgrade/recovery, and tested restore.

The previous capability assessment at `docs/CENTMINMOD-CAPABILITY-GAP.md` is useful but is not a substitute for the more detailed A–O prompt. It is also an older snapshot. This report records the current `main` SHA and the relevant sidecar state so future work does not silently inherit stale claims.

### Important authorization and evidence boundaries

- Repository access was available through GitHub. No local checkout or clean/dirty working-tree state was available through this inspection path.
- GitHub CI for PR #79 was rechecked at head `ef997d4102c7855af4293dbb4a2399dba65da472`: Ubuntu and AlmaLinux 9 both passed `make lint`, `make headers`, and `make test`. This validates that PR head only, not `main`, production hosts, or restoreability.
- No packages, services, firewall, DNS, certificates, databases, or production hosts were changed.
- No privileged VM or real-host integration environment was available or used.
- Centmin Mod is GPL-3.0; StackAlign is MIT. This audit proposes independent behavior, not copying upstream code.
- The sidecar was **not invoked for this audit**. Its configured deployment endpoint and provider credentials are not available through repository inspection. More importantly, the sidecar's inspected `main` revision still contains model-generated Python `eval/exec` in `app/harness.py`. Its own README describes production hardening requirements, and StackAlign's `docs/PINECONE-AGENT-INTEGRATION.md` explicitly says not to deploy that revision as a host-control agent.
- Sidecar PR #1 proposes registered JSON tools, key/session scoping, removal of demo keys, and a non-root container. It remains open. Its PR description says provider-backed end-to-end tests were not run. Do not deploy it merely because the PR exists; review and merge it, pin the resulting commit, run its CI, then validate the isolated deployment contract.
- StackAlign's sidecar client in `lib/agent.sh` is planning-only: it sends read-only doctor and repository-inventory output and prints an answer; it does not execute model output. Its tests use a fake curl executable. They do not prove a live sidecar connection or provider behavior.
- Do not send secrets, credentials, customer data, private keys, or sensitive logs to the sidecar. External provider traffic is a separate data-flow decision requiring operator approval.

## Repository and architecture map

### StackAlign

- Language/runtime: Bash-oriented CLI and modules, with Python 3 used by selected tooling/tests; Makefile drives Bash syntax/ShellCheck where installed, header checks, shell suites, and a Python math test.
- Entrypoints: `install.sh`, `bin/stackalign`, and the oracle helper. The CLI dispatches into modules under `lib/`.
- Core modules visible in the inspected tree include configuration, backup, database, egress, extensions, fetch, firewall, hosting, internet access, LEMP, optimization, repositories, secrets, services, SFTP, sites, TLS, tuning, updates, verification, watchtower, and agent integration.
- Tests are predominantly shell suites under `tests/`, with fixtures and fake executables. CI has Ubuntu and AlmaLinux 9 userland jobs. These are not full fresh-host system tests.
- Configuration: `lib/config.sh` parses INI as data and does not source/eval it. It requires `[meta] config_version=1`, rejects malformed lines and duplicate keys unless explicitly overridden. A typed product schema and atomic persistence/writer are not established by this parser.
- Hosting: site inventory and native Nginx/Apache syntax diagnostics exist; site create/remove/isolate remain fail-closed. Hosting mode planning does not establish tenant isolation.
- TLS: ACME client discovery/selection and HTTP-01 planning exist, but issuance, renewal, atomic deployment, scheduler ownership and live reload/recovery are not established.
- Database: inventory and guarded planning exist; full application user/grant lifecycle and restore recovery remain incomplete.
- Backup: logical/physical backup creation/list/verification exist with explicit limitations. PR #79 adds read-only restore preflight; actual restore remains blocked.
- Sidecar: optional client, read-only snapshot and advisory plan only; no host authority.

### Centmin Mod

- Public repository default branch is `master`, inspected at `4e7aec8585c6ad169773d1a77df17f560e4e0d71`.
- The existing StackAlign assessment also pins the `141.00beta01` source baseline and documents the menu/addon capability catalogue.
- Centmin Mod is a broad, root-oriented LEMP hosting installer with a distinct package/build, filesystem, service and upgrade ownership model. Its capabilities are a reference for operator outcomes, not a reason to chain its installer into StackAlign.
- No upstream Centmin source was copied.

## A–O coverage matrix

Status describes StackAlign evidence, not Centmin Mod parity. “Partial” means a bounded implementation or plan exists; it does not mean the lifecycle is closed.

| ID | Area | Current evidence-based status | Highest-value open gap | Priority |
|---|---|---|---|---|
| A | Installation and bootstrap | Partial / validation gap | Prove supported OS/architecture matrix, package-manager contention, authenticity, rerun and interrupted-install recovery on disposable supported hosts | P1 |
| B | OS integration | Partial / integration gap | Validate systemd, SELinux, firewall coexistence, reboot persistence, timers and log rotation on real EL hosts | P1 |
| C | Nginx and HTTP serving | Partial | Complete safe vhost lifecycle, staged validation/activation/rollback, operator include preservation and real Nginx integration | P1 |
| D | PHP and PHP-FPM | Partial / major lifecycle gap | Per-site identity/pool/socket/resource boundaries, ABI-aware extensions, worker sizing from measured PSS/RSS and OOM behavior | P0/P1 |
| E | Database operations | Partial / recovery gap | Least-privilege app users/grants, secret rotation, supported upgrade policy and tested clean-target restore | P0 |
| F | TLS lifecycle | Partial / planning only | Issuance, renewal, lineage ownership, atomic cert/key deployment, scheduler isolation, failure alerting and real HTTP-01/DNS-01 tests | P1 |
| G | WordPress/application workflows | Partial / scope not fully validated | Decide and document supported application scope; secure install/update/cache/cron/restore lifecycle only if adopted | P2 |
| H | Caching | Partial / limited | No demonstrated complete per-site page/object cache lifecycle, safe cache keys/bypass, invalidation authorization or load tests | P2 |
| I | Security | Partial / test-boundary gap | Complete threat-boundary review and hostile-input/failure tests; prove least privilege and supply-chain behavior on supported hosts | P0 |
| J | Configuration and state | Partial / foundational gap | Typed schema, explicit precedence/defaults, safe atomic writer, mode/owner preservation, migration, drift and concurrency behavior | P0 |
| K | Reliability and lifecycle | Partial / major validation gap | Operation state, lock/revalidation, staged changes, crash recovery, safe retry, rollback boundaries and uninstall preservation tests | P0/P1 |
| L | Backup, restore and migration | Partial / critical recovery gap | Encrypted/manifested backups, retention, off-host verification, clean-target restore drills, RPO/RTO and migration rehearsal | P0 |
| M | Observability and diagnostics | Partial | Structured operation IDs, consistent exit codes, service/resource/certificate diagnostics, redacted support bundle and alerting | P1 |
| N | Performance and resource efficiency | Unknown / measurement gap | Reproducible baseline and workload/host matrix; measured PHP worker memory, tail latency, I/O, swap and OOM results | P2 |
| O | Engineering and delivery | Partial / CI scope gap | Disposable full-system matrix, failure injection, pinned action/dependency policy, release provenance and signed artifacts | P1 |

### Cross-cutting disposition

- **Adopt:** validated configuration, safe staged file updates, operation state/locking, least-privilege DB credentials, tested backup/restore, TLS lifecycle, explicit diagnostics.
- **Adapt:** Centmin Mod's useful hosting, cache, extension, and update outcomes using StackAlign's DNF/package and fail-closed architecture.
- **Defer:** optional runtimes, mail stack, PostgreSQL, dashboards, advanced cache layers, migration automation, and 512 MiB/other constrained profiles until product scope and host measurements justify them.
- **Reject as defaults:** disabling SELinux, globally switching legacy runtimes, unsafe root-script chaining, exposing database/cache/admin ports, automatic destructive malware quarantine, and shared-hosting claims without a validated tenant boundary.

## Verified strengths

1. The configuration parser treats input as data and does not execute it.
2. Backup credential handling uses a protected defaults-file boundary rather than placing database passwords in command arguments.
3. Backup verification is explicit about what it does not prove; restore execution remains blocked.
4. Site inventory and Nginx/Apache syntax checks are read-only; site lifecycle operations fail closed.
5. TLS client discovery and strict selection avoid silent fallback; current issuance planning is not misrepresented as issuance.
6. SFTP tests include adversarial mutation checks; no live sshd operation is claimed.
7. The sidecar client is advisory-only and uses a private temporary header file for the API key rather than curl argv; fake-curl tests check this boundary.
8. Ubuntu and AlmaLinux 9 CI provide useful shell-level regression coverage, but not OS integration evidence.

## Critical findings and first implementation path

### P0 — recovery and configuration safety

1. **Restore is not yet a restore workflow.** PR #79 provides read-only preflight only. It does not execute MariaDB restore, create an isolated target, snapshot the target, roll back, or prove recovery. Do not call restore complete.
2. **Configuration has parsing but no complete product schema/persistence contract.** The current INI parser is deliberately generic. Do not enable unreviewed schema keys or write config files until types, paths, defaults, precedence, permissions, ownership, atomic replacement, symlink policy and migration are specified.
3. **Tenant isolation is not established.** A vhost or document root is not a tenant boundary. Do not enable shared-hosting apply before separate identities, pools/sockets, filesystem/process/resource controls and adversarial integration tests.

### P1 — core hosting lifecycle

4. TLS issuance/renewal/deployment is not end-to-end.
5. Site/vhost create/disable/remove and safe config activation are not complete.
6. Database app-user/grant lifecycle is incomplete.
7. Component update planning is not equivalent to a tested upgrade/rollback system.
8. Service, certificate, resource and support-bundle observability need an operator-oriented completion pass.

### P2 — evidence before tuning/features

9. No valid comparative benchmark or measured constrained-memory support claim is established by the inspected evidence.
10. WordPress, page cache, Redis/Memcached server management, optional runtimes and mail hosting require explicit product-scope decisions and complete tests before adoption.

## Sidecar readiness decision

**Current status: blocked for live use pending PR #1 review/merge and deployment approval.**

Evidence:

- Sidecar `main` SHA: `8260ee84fc6deb96aeebe46079d47948a30cd84d`.
- `app/harness.py` in that revision compiles and executes model-generated Python using `eval/exec` with a restricted builtins dictionary. A restricted builtins dictionary is not a secure Python sandbox.
- `app/tools/sandbox_exec.py` exists but the inspected main agent loop does not call it.
- `.env.example` in main includes demo API-key entries. The config model reads provider credentials and API host defaults; README itself lists authentication and sandboxing as production requirements.
- Sidecar PR #1 (`Harden agent tools and session isolation`) is open and unmerged. Its diff removes arbitrary model-code execution in favor of registered JSON tools, tightens API key parsing/session scoping, removes demo keys, changes container user to UID 10001 and adds CI/tests. These are proposed changes, not yet the deployed sidecar.
- StackAlign `lib/agent.sh` sends read-only doctor/repository inventory and displays the answer only. It does not execute returned code. `tests/test_agent.sh` uses a fake curl binary, so live integration remains untested.
- The sidecar is an optional external-provider data flow. No API endpoint, provider credential, or operator approval for deploying the service was supplied in this repository inspection. No request was sent.

**Required gate before sidecar-assisted full prompt review:**

1. Review and merge sidecar PR #1 (or independently remediate and review the same findings).
2. Pin the reviewed sidecar commit; verify CI and dependency lock/provenance.
3. Deploy only in an isolated, non-root container with no host mounts, Docker socket, host networking, added capabilities or shell/SQL tools; publish loopback only.
4. Obtain explicit approval for provider egress and the exact sanitized data sent.
5. Supply an operator-managed API key through the documented protected mechanism. Never place credentials in a prompt, repository, issue or PR.
6. Run the complete A–O prompt against the sanitized repository evidence and require path/SHA/test references for each material claim.
7. Independently verify every sidecar finding against source/tests; the model is an assistant, not the evidence authority.

## Prioritized backlog and dependency path

| Order | Work item | Priority | Depends on | Definition of done |
|---|---|---|---|---|
| 1 | Complete schema contract and validation for configuration | P0 | Existing parser/tests; explicit product schema decision | Invalid/unknown keys and types fail closed; precedence/defaults and migration documented; no live file write before staged validation |
| 2 | Safe atomic configuration writer | P0 | 1 | Same-filesystem staging, symlink policy, ownership/mode preservation, atomic rename, failure cleanup and concurrency tests |
| 3 | Backup manifest/confidentiality/retention contract | P0 | Existing backup format and secret module | Authenticated integrity metadata, encryption/key handling, retention and destination failure semantics tested |
| 4 | Isolated MariaDB restore drill | P0 | 3; disposable VM approval | Clean-target restore, pre-restore snapshot, engine checks, failure injection and documented rollback/RPO/RTO |
| 5 | Tenant isolation design and disposable adversarial test harness | P0 | OS/platform support contract | Separate Unix identity, FPM pool/socket, filesystem/process/resource limits and cross-tenant denial tests |
| 6 | TLS issuance/deployment/renewal lifecycle | P1 | Secret handling, site config staging, service health | Staging/live issuance tests, atomic activation, reload failure recovery and scheduler ownership |
| 7 | Site lifecycle | P1 | 2, 5, web-server validation | Add/disable/remove plans, operator override preservation, idempotency and rollback tests |
| 8 | DB user/grant lifecycle | P1 | Secret boundary, backup/restore | Least privilege, safe credential handoff, hostile-input and destructive-operation tests |
| 9 | Upgrade/recovery and observability | P1 | 1, 2, service adapters | Version pinning, transaction preview, tested recovery boundaries and actionable diagnostics |
| 10 | Benchmarks and optional application/cache features | P2 | Stable lifecycle + disposable host matrix | Reproducible workloads and measured results before support/performance claims |

## Validation ledger

| Evidence | Result | Scope limitation |
|---|---|---|
| StackAlign main branch metadata | Verified at `ca069223d7ba5ac071d3198508d47f172ad49009` | Remote GitHub view; no local working-tree state |
| Centmin Mod master metadata | Verified at `4e7aec8585c6ad169773d1a77df17f560e4e0d71` | Branch snapshot, not all supported releases |
| Sidecar main metadata | Verified at `8260ee84fc6deb96aeebe46079d47948a30cd84d` | Static source inspection only |
| Sidecar PR #1 | Open, not merged | Proposed hardening only; no live deployment |
| StackAlign PR #79 CI | Ubuntu and AlmaLinux 9 passed at `ef997d4102c7855af4293dbb4a2399dba65da472` | PR head only; no real DB restore |
| Sidecar live API call | Not run | No configured endpoint/credentials; main revision is not safe to deploy |
| Real-host / disposable-VM integration | Not run | No approved environment |
| Performance benchmark | Not run | No benchmark data |
| Clean-host restore drill | Not run | Restore apply remains blocked |

## Source index

StackAlign main `ca069223d7ba5ac071d3198508d47f172ad49009`:
- `docs/CENTMINMOD-CAPABILITY-GAP.md` — existing comparison and adoption assessment.
- `docs/PINECONE-AGENT-INTEGRATION.md` — sidecar trust boundary and deployment gate.
- `lib/config.sh` / `tests/test_config.sh` — non-executing INI parser and parser tests.
- `lib/backup.sh`, `tests/test_backup.sh`, `tests/test_backup_cli.sh` — backup/verification implementation.
- `lib/site.sh`, `tests/test_site.sh`, `tests/test_site_cli.sh` — read-only site diagnostics and blocked lifecycle.
- `lib/tls.sh`, `tests/test_tls_clients.sh`, `tests/test_tls_certbot_plan.sh`, `tests/test_tls_status.sh` — discovery/planning/diagnostics.
- `lib/agent.sh`, `tests/test_agent.sh` — advisory sidecar client and fake transport tests.
- `.github/workflows/ci.yml`, `Makefile` — automated shell-level checks.

Sidecar main `8260ee84fc6deb96aeebe46079d47948a30cd84d`:
- `app/harness.py` — model-generated Python execution risk in inspected main.
- `app/tools/sandbox_exec.py` — sandbox helper not wired into that agent loop.
- `app/main.py`, `app/auth/middleware.py`, `app/config.py` — API and auth configuration.
- `tests/test_smoke.py` — minimal smoke/sanitization coverage in main.
- PR #1 — proposed structured-tool/auth/container hardening.

Centmin Mod:
- `master` SHA above and existing `141.00beta01` baseline in the prior StackAlign comparison report.
- `LICENSE` is GPL-3.0; StackAlign `LICENSE` is MIT.
