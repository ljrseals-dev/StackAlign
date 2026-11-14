# StackAlign

An early-stage Bash-based foundation for a pre-tuned LEMP (Nginx, MariaDB, PHP-FPM) installer and manager, targeting EL-family x86_64 servers.

**StackAlign does not install a web stack yet. It is not production-ready.**

## Project status — 14 November 2026

StackAlign is an experimental foundation intended for review and disposable-environment testing. The project follows one rule: **measure, do not claim**.

### Implemented and integrated

The following capabilities are present in `main`. Their stated validation boundaries still apply.

- **Core CLI and foundation:** `version`, `help`, `plan`, `doctor`, `rollback`, and `secret gen/list`; configuration, rendering, history, service, and repository helpers.
- **Repository manifest pins:** `vendor/versions.toml` is parsed for component pins. Invalid, duplicate, malformed, or missing requested pins fail closed. The manifest's `tested_matrix` values are empty; they do not establish a supported host matrix.
- **RPM cache verification:** package cache entries are checked against exact NEVRA and RPM signature verification before reuse. Tests use fake package tools; real repository/signing-key and host package flows remain unverified.
- **Manual package updates:** `stackalign update apply` uses a transactional update path with configuration snapshot/service-health handling and RPM downgrade recovery. `watchtower` is advisory. CI exercises mocked failure and rollback paths; no live DNF transaction, service restart, or real-host rollback has been validated.
- **Render-plan portability:** plan/apply comparisons use named temporary files rather than process substitution; diff errors are distinguished from ordinary differences.
- **History undo safety:** generated undo scripts use PID-scoped stage and backup names.
- **Nginx AI-crawler matching:** additional crawler user-agent patterns are included in the existing map. `make lint` and `make test` passed on the PR head; `nginx -t` against a fully rendered configuration has **not** been run.
- **Release-artifact verification foundation:** `lib/verify.sh` verifies a detached GPG signature over `SHA256SUMS`, an independently provisioned keyring and pinned primary-key fingerprint, signed metadata expiry, and artifact SHA-256. See [Release Artifact Trust](docs/RELEASE-TRUST.md).

### Documentation and policy records

- [Technical Manual](docs/Technical%20Manual.md) records the FTP server boundary: StackAlign does not install or configure an FTP daemon, but an operator may run an independently installed and managed FTP server. Ordinary authenticated client-to-server uploads/downloads remain permitted; FTP-to-FTP third-party transfers (FXP) are to be refused. **Software enforcement is unverified.** FTPS behavior is not specified by that policy note.
- [TLS client design](docs/TLS-CLIENTS.md) documents Certbot, acme.sh, and Lego lineage ownership. It is a design document only; it does not install clients, issue certificates, configure schedulers, or implement runtime TLS orchestration.
- [Clean-room provenance audit](docs/design/clean-room-provenance-audit.md) records **RISK DETECTED — provenance incomplete**, including unresolved imported archive/document rights and missing provenance evidence. This is not a finding that GPL code is present and is not a legal opinion.

### Not implemented or not validated

- StackAlign does **not** install Nginx, PHP-FPM, or MariaDB as a complete web stack. `install.sh` refuses to run until a release hash is pinned.
- The release verifier is not wired into `install.sh` or an update workflow. Its downgrade helper is not yet bound to a signed release manifest. No self-update mechanism is included.
- TLS runtime orchestration, certificate issuance/renewal, backups, tenant management, and production FTP/SFTP service management are not established as complete StackAlign workflows. The egress firewall is an opt-in module only: it is not persistent, not enabled by install/update/boot, and not validated on a real kernel or disposable VM.
- The manual update path has not been validated against a real DNF repository, package transaction, running service, or real-host rollback.
- The Nginx crawler-map change still needs `nginx -t` against a rendered configuration.
- No real-host signing-key lifecycle, package-update, SSH chroot, or production runtime validation is claimed.
- CI success proves only the checks run against the specific commit. It does not prove installation, isolation, recovery, security, performance, or production readiness.

### Outstanding integration work — not included in main

Three draft pull requests remain open and are not part of the integrated baseline:

- [PR #10 — read-only update planning](https://github.com/ljrseals-dev/StackAlign/pull/10): `stackalign update plan` and T36 coverage remain outstanding. The latest recorded CI attempts for its head failed. Do not describe this work as superseded by the separate manual `update apply` path.
- [PR #26 — operational library modules](https://github.com/ljrseals-dev/StackAlign/pull/26): the latest recorded CI attempts for its head failed. Its firewall/FTP behavior must be reconciled with the policy below before merge: ordinary authenticated client-to-server FTP remains permitted when an independently installed and managed FTP server exists; FTP-to-FTP third-party transfers (FXP) are refused. Do not reject all FTP use.
- [PR #28 — chrooted key-only SFTP management](https://github.com/ljrseals-dev/StackAlign/pull/28): the latest recorded CI attempts for its head failed. Real OpenSSH configuration validation, chroot isolation, key-only login, and preservation of ordinary login behavior remain unverified.

These PRs require corrective changes and passing required CI before merge. PR #28 additionally requires disposable-host OpenSSH/chroot validation. Until then, they are release blockers, not implemented capabilities of `main`.

## CI and validation

GitHub Actions completed the post-merge `main` run successfully for commit `3e51169484e42083d9ead1364577ca6b24e910a6`: [run 43556286513](https://github.com/ljrseals-dev/StackAlign/actions/runs/43556286513). That run is the CI result for the integrated tree at that commit. It does not cover the three open draft PRs below, nor does it establish real-host behavior.

Use precise evidence labels:

- **PASS** — the named check ran and passed on the stated commit/environment.
- **FAIL** — the named check ran and failed.
- **NOT RUN** — no result exists.
- **UNVERIFIED** — implementation or behavior has not been established by the required evidence.
- A design, source file, test, or CI run is not proof of real-host behavior.

## Early testers wanted

We welcome people who want to inspect the foundation, run its checks, and report defects.

**Safety requirements:**

- Use disposable containers or virtual machines only.
- Prefer throwaway AlmaLinux 9 or Rocky Linux 9 environments for EL-family testing.
- Never run StackAlign on a machine that matters or with real credentials.
- Do not use production systems or important data.
- Redact passwords, tokens, private keys, and other secrets from all reports.

Start with the [Early Tester Call](docs/EARLY-TESTER-CALL.md). Report the distribution and version, kernel, architecture, VM/container type, exact commands, complete output, failures, and reproducible steps.

## Memory tuning and measurement status

The M2a arithmetic implementation and contract tests are present. The current pinned test floors are T27 = 391 MiB and T28 = 3389 MiB.

The M2b measurement gate remains open:

- `SA_PHP_CHILD_MIB=30` is a provisional assumption, not a measured worker footprint.
- Fixed service costs are also assumptions pending representative host measurements.
- The 512 MiB no-swap case has been checked arithmetically, not load-tested on a real 512 MiB VM.
- `m2b/measure-php-child-rss.sh` is provided to collect PHP-FPM worker PSS under baseline and heavier workloads. Its output must be collected on a real test host; it is not evidence until actually run.
- Do not change the tuning assumptions or claim M2b completion without reviewing the physical measurements.

No measured sizing table or performance, security, stability, or recovery-time claim is published.

## Scope and operating principles

- Intended deployment scope: EL-family Linux on x86_64. Ubuntu 24.04 is used as a CI environment, not currently a supported deployment target.
- Bash for installer and runtime code. Python is used for development-time tests and benchmarks.
- Package operations use DNF and upstream packages; StackAlign does not build source replacements or forks of Nginx, PHP, or MariaDB.
- Manual update application is distinct from unattended/self-update behavior; no unattended updater is provided.
- No secrets in the repository, logs, snapshots, or Git history.
- No telemetry, network bootstrap, or hidden remote configuration.
- Keep measured results, CI results, and design assumptions clearly distinguished.

The [Security Architecture Comparison](docs/SECURITY-ARCHITECTURE-COMPARISON.md) records StackAlign's DNF-first package policy, repository trust requirements, software lifecycle rules, rollback expectations, clean-room provenance boundaries, and implementation acceptance gates. It is a policy/design document, not evidence that those controls are already implemented.

## Development

Use focused feature branches and pull requests. Preserve existing history and never force-push. Keep `main` protected from unreviewed changes. A merge or passing CI job is not evidence of successful installation or production operation.

## License

MIT. See [LICENSE](LICENSE).
