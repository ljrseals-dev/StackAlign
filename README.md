# StackAlign

A standalone Bash-based LEMP installer and manager for supported Enterprise Linux (EL) systems on x86_64.

StackAlign is intended to make server configuration explicit, reproducible, reviewable, and honest about resource limits. It is not a performance benchmark, and it must not claim that a server is secure, isolated, correctly sized, or production-ready merely because a configuration file was generated.

## Project status — 12 November 2026

**Bootstrap code is present. The frozen M2a tuning contract is not implemented or verified. The project is not ready to be described as a complete installer or production-ready server manager.**

The default branch, `main`, currently contains an initial CLI, configuration parsing and support libraries, shell test suites, and a provisional tuning function. These are real repository files, but their presence must not be confused with completion of the planned system.

The most important current limitation is `lib/tune.sh`:

- It implements only a provisional lean-profile calculation.
- It uses a 32 MiB per-PHP-child estimate that is explicitly an unmeasured assumption.
- It returns `standard_not_implemented` for the standard profile.
- Its current connection calculation uses a zero worker-connection allowance.
- The CLI `tune` command is not wired to this function.
- It is not an implementation of the complete frozen M2a tuning contract.

The current `tests/test_tune_math.py` suite contains five provisional tests. They exercise the Bash function, but they are **not** the frozen T1–T28 acceptance matrix and do not establish M2a compliance.

The documentation work describing the intended tuning contract is on the open `work/initial-bootstrap` pull request, not on `main`. The documentation PR is not merged. Until the reviewed contract is present on the default branch and the implementation passes its required tests, the design contract and provisional code must remain clearly distinguished.

## Target environment

### Intended runtime targets

- Enterprise Linux family: AlmaLinux and Rocky Linux.
- Architecture: x86_64.
- Target major versions: EL 9 and EL 10, subject to explicit support and validation for each distribution/version combination.
- Installer and runtime language: Bash.
- Python is permitted for development-time test drivers, quality checks, and benchmarks; it is not the installer/runtime implementation language.

A distribution being EL-compatible does not, by itself, prove that StackAlign supports it. Support must be stated for the exact distribution and major version and backed by checks on that environment.

### CI is not the same as target-host validation

The current CI repair is tracked in open pull request #2, `fix/ci-lint-and-executable-mode`. Its recorded workflow run passed the Ubuntu and AlmaLinux 9 jobs:

- Ubuntu: lint passed with ShellCheck installed; tests passed.
- AlmaLinux 9: Bash syntax/lint checks passed and tests passed. ShellCheck was unavailable in that container and the Makefile explicitly skipped that check.
- The five provisional tuner tests passed in that run.

This is evidence about the tested pull-request revision and those CI jobs only. It does **not** mean that PR #2 has been merged, that `main` is green, that EL 10 has been tested, or that a real server installation or production runtime has been validated. Ubuntu is a CI environment here, not a supported StackAlign deployment target.

## Scope

StackAlign is limited to managing LEMP servers and supported self-hosted PHP application workloads. Hosted SaaS services are outside the scope of server-side tuning. Unrelated application domains and services should not be added to the project.

Planned workload coverage includes generic PHP, WordPress/WooCommerce, Laravel, and selected self-hosted applications. X-Cart 5.6 is treated as a guarded LEMP workload profile. Its 2 GiB policy floor is advisory: falling below it should produce a clear warning and sizing guidance, not an automatic refusal. A sizing refusal must be based on arithmetic infeasibility, not solely on a policy recommendation.

A `slave_web` role represents a web-only node behind an upstream load balancer or DNS rotation. Local MariaDB and Redis costs must be derived from the selected role and explicit configuration inputs; a web-only node must not silently reserve memory for services it does not host.

These are design requirements. They must not be presented as implemented behavior until the corresponding code and tests exist.

## What exists now

| Area | Honest status |
|---|---|
| Repository/bootstrap structure | Present on `main` |
| Bash CLI and support modules | Present; not proof of a complete installer |
| Configuration parser | Present; full proposed schema/contract is not complete |
| Tuning function | Provisional lean-only implementation |
| Standard tuning profile | Not implemented; currently refuses explicitly |
| Workload and role-aware cost resolution | Not complete |
| CLI integration for the tuner | Not wired |
| Tuner tests | Five provisional tests; not T1–T28 |
| Full frozen M2a contract | Not implemented or verified |
| Documentation contract | In open PR #1; not merged to `main` |
| CI repair | Open PR #2; its recorded Ubuntu and AlmaLinux 9 jobs passed |
| EL 10 validation | Not established |
| Real-host installation/runtime validation | Not established |
| Production readiness | Not established |

A passing test suite means only that the tests actually run passed. A passing pull-request workflow does not establish that the default branch is green. A successful build does not establish installation correctness, runtime behavior, tenant isolation, or production readiness.

## What is needed next

The following work is required before StackAlign can make stronger implementation or readiness claims.

1. **Complete the documentation baseline.** Review the documentation in PR #1, including the exact frozen tuning arithmetic, policy-versus-arithmetic rules, workload inputs, role behavior, and implementation-status record. Keep proposed material visibly separate from frozen requirements.
2. **Recover and preserve the complete frozen acceptance contract.** The T1–T28 cases and exact standard-profile arithmetic must be available as authoritative project documentation. Do not reconstruct missing test cases from guesses or publish hand-calculated sizing tables as implementation output.
3. **Resolve the separate fixed-size settings proposal.** The proposed §8.2 work remains proposed and not frozen. Its temporary-table budget edge case, internally consistent table-cache fixtures, and controlled systemd file-limit tests must be corrected and reviewed before it becomes a requirement.
4. **Implement the full tuner.** Add the standard profile, exact lean/standard selection rules, input validation, workload registry, role-aware service costs, explicit overrides, advisory warnings, and documented refusal reasons.
5. **Connect the implementation to the CLI.** The user-facing `tune` path must call the real implementation and report the effective inputs, calculated values, warnings, and refusal reason. It must not silently substitute defaults or imply that an unimplemented profile succeeded.
6. **Replace provisional tests with contract tests.** Execute the frozen T1–T28 cases against the actual Bash implementation, add the separately approved tests only after their contract is frozen, and verify boundary cases and invalid input behavior.
7. **Validate supported hosts.** Run installation, upgrade/recovery, service configuration, and runtime checks on each explicitly supported AlmaLinux/Rocky Linux major version. Record exact OS image/version, commands, results, and known limitations.
8. **Keep evidence current.** Record which branch and commit were tested, which CI jobs ran, which checks were skipped, and what remains untested. Do not convert a PR-only green result into a claim about `main`.

## Operating and security principles

- No unattended update application.
- No network bootstrap, telemetry, or hidden remote configuration.
- No secrets in the repository, logs, snapshots, or Git history. Runtime secrets belong under `/etc/stackalign/secrets/` with restrictive permissions; snapshots exclude them by default.
- Treat configuration values as data. Do not execute shell fragments supplied through configuration.
- Do not claim tenant isolation from configuration strings alone. Isolation requires tests with live tenants and verification of the actual enforcement boundary.
- Do not claim performance, memory savings, security guarantees, or recovery times without reproducible measurements.
- Keep sizing formulas and sizing tables centralized in the authoritative tuning document. Publish generated sizing output only when it comes from the implementation and documented test inputs.
- Distinguish design, implementation, automated tests, CI, target-host validation, and production operation in every status report.

## Development workflow

Use focused changes with reviewable commits. Preserve existing history and never force-push. Changes should normally be developed on short-lived branches and reviewed through pull requests. A direct update to `main` should be exceptional and explicitly authorized. Never treat a merge as proof of successful installation or runtime validation.

## License

MIT. See [LICENSE](LICENSE).
