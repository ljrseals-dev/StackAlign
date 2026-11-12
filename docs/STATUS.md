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
