# StackAlign

**Controlled pre-production beta — not for production use**

StackAlign is a Bash-based foundation for a planned, auditable LEMP deployment and management system targeting Enterprise Linux x86_64 servers.

**This repository does not yet provide a complete Nginx, PHP-FPM, and MariaDB installer.** The bootstrap installer intentionally refuses to proceed until a release hash is pinned. Do not deploy StackAlign to production systems, business-critical workloads, or hosts containing valuable data.

The project follows one rule: **measure, do not claim.** Implementation, automated tests, CI results, disposable-host validation, and production readiness are separate things.

## Join the beta

We welcome testers who can use disposable environments, report reproducible defects, and submit focused pull requests.

1. Read the [Early Tester Call](docs/EARLY-TESTER-CALL.md).
2. Follow the [Beta Testing Guide](docs/BETA-TESTING.md).
3. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or PR.
4. Review the [Technical Manual](docs/Technical%20Manual.md) and its verification labels.

**Safety rules:** disposable AlmaLinux 9 or Rocky Linux 9 VM/container only; no production hosts, real credentials, valuable data, or public exposure of test services. Snapshot before privileged tests. Redact secrets and personal data from every report.

## Current project status

StackAlign is an evolving foundation. The following areas are present in the repository; their verification limits remain part of the status.

### Implemented in the repository

- **CLI foundation:** version, help, plan, doctor, rollback, secret helpers, and command dispatch.
- **Configuration and operations helpers:** configuration parsing, rendering, history, service and repository helpers.
- **Repository manifest pins:** component pins are parsed from the manifest; malformed, duplicate, or missing requested pins fail closed. The manifest does not establish a supported host matrix.
- **RPM cache verification foundation:** cache entries are checked against exact NEVRA and RPM signature verification before reuse. Tests use fake package tools; real repository/key and host package flows remain unverified.
- **Manual package updates:** update apply has a transactional path with configuration snapshot/service-health handling and RPM downgrade recovery. CI uses mocked failure and rollback paths; live DNF transactions and real-host rollback remain unverified.
- **Read-only update planning:** update plan is integrated separately from update apply.
- **Experimental operational modules:** operational libraries are present, but their existence does not establish complete firewall, ACME, backup, antivirus, or daemon-management workflows.
- **Chrooted key-only SFTP management:** integrated with disposable OpenSSH configuration and transfer tests in CI. Applying it changes system accounts and SSH configuration; it is not certified for production hosts.
- **Release artifact verification foundation:** detached GPG signature, independently provisioned keyring/fingerprint, metadata expiry, and SHA-256 verification helpers exist. The verifier is not yet wired into installer/update workflows.
- **Memory tuning:** arithmetic implementation and contract tests exist. Physical PHP worker measurements and representative low-memory VM testing remain outstanding.

### Not implemented or not validated

- Complete installation and lifecycle management of Nginx, PHP-FPM, and MariaDB.
- A pinned, verified release artifact integrated into the installer and update path.
- End-to-end live DNF transactions, service changes, and real-host rollback validation.
- TLS runtime orchestration, certificate issuance/renewal, backups, firewall management, and tenant isolation as complete StackAlign workflows.
- Physical memory measurements, load testing, and measured performance claims.
- Production host security, isolation, recovery, and stability validation.
- Complete release signing-key lifecycle and production release process.

### FTP policy boundary

StackAlign does **not** install or configure an FTP daemon. An operator may independently install and manage one. Ordinary authenticated client-to-server uploads and downloads are intended to remain permitted; FTP-to-FTP third-party transfers (FXP) are specified to be refused. **FXP software enforcement is unverified.** This is not a firewall-enforcement claim, and FTPS behavior is separate. See the [Technical Manual](docs/Technical%20Manual.md).

### Provenance and licensing

The project is MIT-licensed. The [clean-room provenance audit](docs/design/clean-room-provenance-audit.md) records **RISK DETECTED — provenance incomplete**, including unresolved imported archive/document rights and missing provenance evidence. This is not a finding that GPL code is present and is not a legal opinion. Do not treat the MIT license declaration as a substitute for resolving the recorded provenance work.

## CI and validation

GitHub Actions runs lint and test jobs on Ubuntu and an AlmaLinux 9 container for pushes and pull requests. Check the [Actions page](https://github.com/ljrseals-dev/StackAlign/actions) for the result associated with the exact commit you are reviewing.

Run the local checks from a development checkout:

```bash
make lint
make test
```

Use evidence labels precisely:

- **PASS** — the named check ran and passed on the stated commit/environment.
- **FAIL** — the named check ran and failed.
- **NOT RUN** — no result exists.
- **UNVERIFIED** — behavior or implementation has not been established by the required evidence.
- **SPECIFIED** — documented design/policy, not proof of implementation.

CI success proves only that the named checks passed on that commit. It does not prove installation, security, isolation, recovery, performance, or production readiness.

## Contributing

Use focused feature branches and pull requests. Do not commit directly to main or force-push shared history. Add tests for changed behavior, update relevant documentation, and state exactly what was and was not tested. Maintainers review contributions before merge.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution process and [SECURITY.md](SECURITY.md) for vulnerability reporting. These documents describe project expectations; do not assume GitHub branch protection is configured unless repository settings confirm it.

## Beta exit criteria

Before StackAlign is represented as production-ready, maintainers must record evidence for:

- A declared supported host matrix and clean installation/upgrade/uninstall lifecycle.
- Disposable-host integration testing on every declared EL target.
- Package-source and signing-key trust verification.
- Failure-injected transaction and rollback validation, including service health.
- Security review of privileged paths, secrets, SSH/account management, and network exposure.
- Physical memory measurements and representative load testing.
- Completed provenance review and accurate third-party notices.
- Verified release artifacts, checksums, signed tags, and documented signing-key lifecycle.
- A Technical Manual and README that match the implemented code and captured evidence.

These are outstanding acceptance gates, not claims of completion. Until then, StackAlign remains a controlled pre-production beta.

## Project principles

- EL-family Linux on x86_64 is the intended deployment scope. Ubuntu 24.04 is a CI environment, not a declared deployment target.
- Bash for installer/runtime code; Python is used for development-time tests and benchmarks.
- DNF-first package management; no source-build replacements or forks of Nginx, PHP, or MariaDB.
- Manual update application is distinct from unattended/self-update behavior; no unattended updater is provided.
- No secrets in the repository, logs, snapshots, or Git history.
- No telemetry, network bootstrap, or hidden remote configuration.
- Keep measured results, CI results, implementation status, and design assumptions distinct.

## License

MIT. See [LICENSE](LICENSE).
