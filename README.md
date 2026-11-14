# StackAlign

An early-stage Bash-based foundation for a pre-tuned LEMP (Nginx, MariaDB, PHP-FPM) installer and manager, targeting EL-family x86_64 servers.

**StackAlign does not install a web stack yet. It is not production-ready.**

## Project status — 13 November 2026

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
- TLS runtime orchestration, certificate issuance/renewal, backups, firewall management, tenant management, and production FTP/SFTP service management are not established as complete StackAlign workflows.
- The manual update path has not been validated against a real DNF repository, package transaction, running service, or real-host rollback.
- The Nginx crawler-map change still needs `nginx -t` against a rendered configuration.
- No real-host signing-key lifecycle, package-update, SSH chroot, or production runtime validation is claimed.
- CI success proves only the checks run against the specific commit. It does not prove installation, isolation, recovery, security, performance, or production readiness.

## CI and validation

GitHub Actions has run `make lint` and `make test` on Ubuntu and AlmaLinux 9 for the integrated feature PR heads. The update transaction PR passed both jobs. The current `main` integration state should be checked against the [main-branch workflow runs](https://github.com/ljrseals-dev/StackAlign/actions?query=branch%3Amain); PR-head CI results are not a substitute for a run on the final merged tree.

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
