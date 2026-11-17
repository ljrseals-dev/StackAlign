# Project status

**2026-11-12 — post-M2a merge status reconciliation**

## Verified repository facts

- GitHub repository: ljrseals-dev/StackAlign
- Default branch: main
- Documentation branch: work/initial-bootstrap
- MIT license is present.
- M2a tuner implementation and T1–T28 contract tests are merged to `main` in commit `43c0fe82d12da07662f1b869ee62e33b605f63ad`.
- This documentation branch carries the corresponding tuning contract and workload-policy design; PR #1 remains open.

## Design documentation

| Area | State | Notes |
|---|---|---|
| Project scope and operating principles | Written | README |
| Tuning arithmetic contract | Implemented and CI-tested | `lib/tune.sh` and T1–T28 tests are on `main`; CI run 43251330070 passed lint and tests on Ubuntu 24.04 and AlmaLinux 9. No worked sizing table is published. |
| Workload registry | Implemented; measurements pending | Registry and role-aware service-cost resolution are implemented in the M2a tuner. Numeric workload/service costs remain assumptions pending M2b measurement. |
| Configuration schema | Written; schema validation pending | A generic INI parser exists on main; the proposed schema and its validation are not implemented. |
| Slave-web role | Implemented as tuner input behavior | `slave_web` defaults to zero local MariaDB base cost unless explicitly overridden. Host discovery/measurement remains out of scope. |
| Tenant isolation contract | Written; implementation and live tests pending | Two-live-tenant M2b verification required. |

## Implementation status

| Area | State | Next action |
|---|---|---|
| CLI/runtime | Bootstrap present; incomplete | Wire only commands whose milestone contracts are implemented; other commands remain stubs. |
| lib/config.sh | Generic INI parser present | Implement and test the approved schema, validation, and compatibility rules. |
| lib/tune.sh | M2a implementation merged | Lean and standard arithmetic, reserve decomposition, strict numeric validation, worker-aware connection budgeting, advisory warnings, workload/role validation, and arithmetic-floor reporting are implemented. Inputs marked `assumption=` remain unmeasured. |
| tests/test_tune_math.py | T1–T28 contract suite merged | T1–T28 includes the pinned arithmetic floors T27 = 391 MiB and T28 = 3389 MiB. Both CI matrix jobs passed lint and test. |
| Tenant isolation modules and templates | Not implemented | Implement only after design review. |
| Upstream version pins | Not populated | Verify from official upstream sources. |
| Application profiles | Not implemented | Add only with compatibility evidence. |
| Transactional deployment | Not implemented | Design rollback and health-check contract before enabling. |
| CI | M2a validation passed | Workflow 43251330070 passed `make lint` and `make test` on Ubuntu 24.04 and AlmaLinux 9 for PR #3 head `e4622d4`; merge commit `43c0fe8` is on `main`. |
| EL-family integration tests | Not run | Requires supported distribution containers/VMs. |
| Two-live-tenant isolation tests | Not run | Required at M2b; config-only checks do not qualify. |
| 512 MiB VM tests | Not run | Requires controlled swap-on/off VM cases. |
| Landlock feature tests | Not run | Required on actual supported EL kernels before M7 opt-in. |

## Validation policy

Record checks as PASS, FAIL, NOT RUN, or BLOCKED. A written design is not implementation; a conversation-only draft is not a repository file; a written test plan is not a test result. A passing CI job proves only the checks that actually ran against that commit. No performance, memory, isolation, or recovery-time claim is validated unless reproducible evidence is recorded.

This PR updates documentation only; the M2a implementation and tests were merged separately in PR #3.


## Timestamped policy clarification — 2026-11-13

| Area | State | Verified notes |
|---|---|---|
| FTP server availability | Specified; implementation unverified | Intended policy retains ordinary client-to-server FTP upload/download capability only for an independently installed and managed FTP service; StackAlign does not install or configure that daemon. StackAlign's current README says firewall management and web-stack installation are not built. |
| FTP-to-FTP / third-party transfer | Specified; software enforcement unverified | Third-party FTP/FXP transfers using an independently managed FTP service on the StackAlign host as a transfer endpoint must be refused. This must not disable the FTP server or block ordinary client-to-server transfers. No firewall-only enforcement is claimed. |
| FTPS and SFTP | Not specified by this clarification | Separate protocols; their availability and firewall policy must not be inferred from the FTP rule. |

**Verification record:** At 2026-11-13T13:05:19-06:00 (America/Chicago, UTC-06:00), README.md on main was checked and states that firewall management is not built and StackAlign is not production-ready. A repository-scoped GitHub code search for FTP/FTPS/SFTP/firewall terms returned no indexed matches. This is a source/status check only, not a runtime test.

**Checks:** Documentation/source inspection: PASS. FTP daemon configuration inspection: NOT RUN (no daemon implementation identified in the checked main documentation/search). Client-to-server FTP test: NOT RUN. FTP-to-FTP/FXP refusal test: NOT RUN. Firewall enforcement test: NOT RUN.

<!-- Review comment: 2026-11-13T13:05:19-06:00; additive status entry. Prior status statements and project wording retained. -->
<!-- Verification comment: PASS applies only to checking the cited documentation and search result. It does not mean FTP policy enforcement or transfer tests passed. -->


**Manual alignment — 2026-11-13T13:09:34-06:00:** `docs/Technical Manual.md` on `main` was fetched and its Section 3.3 exclusion was confirmed. The original statement that StackAlign does not install or configure FTP servers is retained. The added clarification permits only an independently installed/managed FTP service, preserves ordinary client/server transfers, and specifies software-level rejection of FTP-to-FTP/FXP. This remains **SPECIFIED / UNVERIFIED**; no daemon configuration or runtime transfer test has been performed.

<!-- Manual-alignment review comment: 2026-11-13T13:09:34-06:00; additive note only. Existing status entries retained. -->


## Apache hosting modes — feature branch implementation

**Branch:** `feat/apache-upstream-hosting`

| Area | State | Evidence / boundary |
|---|---|---|
| Hosting mode contract | Implemented | `nginx`, `apache`, and `hybrid` read-only plans in `lib/hosting.sh`. |
| CLI planner | Implemented | `stackalign hosting plan <mode>`; no host mutation. |
| Apache capability inspection | Implemented; host result NOT RUN | `stackalign hosting doctor` checks server binaries and proxy modules when Apache is installed. |
| Apache package install/configuration | BLOCKED | No DNF install or service/config mutation is exposed pending isolation and EL9 acceptance gates. |
| Nginx-to-Apache runtime routing | SPECIFIED | Hybrid plan reserves loopback `127.0.0.1:8081`; no listener or proxy configuration is installed. |
| PHP-FPM tenant separation | NOT IMPLEMENTED | Dedicated pool/socket and tenant process ownership remain required. |
| Automated tests | Added; execution NOT RUN in this GitHub-only edit session | `tests/test_hosting.sh` and `tests/test_hosting_cli.sh`; CI must execute them on the PR head. |
| Real-host validation | NOT RUN | AlmaLinux 9 and Rocky Linux 9 disposable VM tests remain required. |

The existing `install` command and LEMP beta behavior are unchanged. No claim of Apache installation, live upstream routing, tenant isolation, or production readiness is made.


### Hosting scope prompt — 2026-11-17

| Area | State | Evidence / boundary |
|---|---|---|
| Interactive operator scope prompt | Implemented; runtime interaction NOT RUN | `stackalign hosting setup` distinguishes a single administrator managing multiple accounts from multiple independent end users. |
| Scope persistence | NOT IMPLEMENTED | The command reports the selected scope but does not write configuration; no approved durable config schema exists yet. |
| Independent-user shared hosting | BLOCKED | No multi-user isolation claim; per-user identities, dedicated PHP-FPM pools/sockets, filesystem/process/resource/service boundaries, and adversarial tests remain required. |
| Mode-specific doctor | Implemented; live host inspection NOT RUN | `hosting doctor nginx|apache|hybrid` checks only the selected mode's binaries and Apache modules where applicable. |

The shared PHP-FPM `www` pool is explicitly not treated as tenant isolation. This work does not change the existing LEMP bootstrap or enable Apache apply.


## Internet access wizard — feature branch implementation

**Branch:** `feat/internet-access-wizard` (stacked on `feat/apache-upstream-hosting`; neither change is merged to `main`).

| Area | State | Evidence / boundary |
|---|---|---|
| Access-purpose questions | Implemented in CLI source | Public website, private administration, or both. Interactive execution NOT RUN. |
| Separate access choices | Implemented in CLI source | DNS provider, public ingress (Cloudflare Tunnel/direct origin), and private administration (Tailscale/WireGuard/existing VPN) are independent fields. |
| Input/config validation | Implemented; CI PASS | Domain and public IPv4 validation; versioned config rejects symlinks, wrong ownership, broad permissions, duplicate/unknown keys, and incomplete records. CI run 702 passed `make lint` and `make test` on Ubuntu and AlmaLinux 9 at head `517aca32bd6f02f42df2c8475cf034904fdb85ba`. |
| Preference persistence | Implemented in CLI source | Non-secret versioned preferences only; atomic write and owner-only permissions; interactive TTY persistence test NOT RUN. |
| Read-only doctor | Implemented; mock tests CI PASS | Reports interface/default-route/DNS failures and checks resolution of `example.com`; real-host inspection NOT RUN. |
| Provider authentication, DNS mutation, TLS, firewall, tunnel installation | NOT IMPLEMENTED / BLOCKED | No provider credentials are collected; no host/network changes are made. |
| End-to-end reachability and recovery | NOT RUN | Requires disposable EL9 host and provider integration tests. |

The CLI explicitly refuses `internet apply`. It must not claim that saving preferences makes a domain or account reachable. DNS provider, public ingress, and private administration are separate choices; Cloudflare Tunnel routing is not represented as direct-origin A/AAAA DNS. Unknown provider, DNS, router/NAT, or cloud-firewall settings require manual instructions.
