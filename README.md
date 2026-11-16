# StackAlign

**A Bash-based Linux operations toolkit for guarded installation, package workflows, and host administration.**

StackAlign is an experimental project for EL-family Linux systems. Its current LEMP bootstrap is deliberately narrow: it installs distribution-packaged Nginx, MariaDB, and PHP-FPM on EL9 x86_64 and exposes a PHP endpoint on loopback only.

> [!WARNING]
> **Experimental beta — not production-ready.** Use disposable virtual machines or containers only. Do not run this project on production hosts, machines containing important data, or systems with real credentials. A passing test suite is not proof of safe real-host operation.

## What StackAlign is

StackAlign combines a Bash CLI, operational shell libraries, tests, and documentation. Its design emphasizes:

- Plan before apply; mutating workflows require explicit opt-in.
- Distribution packages and the host's configured package repositories.
- No hidden telemetry, network bootstrap, or remote configuration.
- No secrets committed to the repository, logs, or snapshots.
- Clear separation between implemented behavior, design intent, mock-test coverage, and real-host validation.
- Evidence before performance, security, compatibility, or recovery claims.

StackAlign is not a general-purpose hosting panel, an unattended updater, or a production deployment system.

## Current implementation

The repository contains the following implemented areas. Each item is subject to the validation limits stated below.

| Area | Current behavior | Important boundary |
|---|---|---|
| CLI foundation | Version/help, planning, read-only doctor, rollback/history, secret helpers, and supporting libraries | The CLI contains recognized commands that are still stubs or gated; command names alone do not mean the workflow is implemented. |
| EL9 LEMP bootstrap | Plans or applies installation of Nginx, MariaDB, PHP-FPM, and PHP MySQL support from already-enabled DNF repositories | EL9 x86_64 only; loopback endpoint; mock-tested, not yet established as a production installer. |
| Package trust/cache | RPM cache checks use exact NEVRA and RPM signature verification | Real repository/key lifecycle and host package flows remain unverified. |
| Manual package updates | Transaction-oriented update path includes configuration snapshots, service-health handling, and RPM downgrade recovery | No live DNF transaction or real-host rollback has been validated. |
| Egress controls | Opt-in nftables OUTPUT policy and passive neighbour-cache inspection | Non-persistent, not enabled automatically, and not validated on a real kernel/network. |
| Release verification | Detached GPG signature, pinned primary-key fingerprint, signed metadata expiry, and artifact SHA-256 verification foundation | Not yet integrated into the release installer or update workflow. |
| Oracle Linux migration wrapper | Guarded CentOS 7/8 conversion wrapper and Oracle Linux 7/8 update wrapper | Fake-tool tests only; live conversion and package updates have not been run. |
| SFTP module/tests | Chrooted key-only SFTP policy and a real-sshd integration test path | CI coverage is not a substitute for disposable-host validation. |

The current LEMP bootstrap is limited to distro-provided packages and an Nginx listener on `127.0.0.1:8080`. It does not configure public ingress, TLS, DNS, firewall rules, application databases/users, tenant isolation, backups, or production hardening. See [LEMP beta guide](docs/LEMP-BETA.md).

## Quick start

### Requirements

- Bash
- GNU/Linux environment
- `make`
- Python 3 for the complete test suite
- EL9 x86_64 for the LEMP apply path
- Root privileges only for explicitly applied system changes

Ubuntu 24.04 is used as a CI environment; it is not currently a supported deployment target for the LEMP bootstrap.

### Inspect the CLI

From a checkout:

```bash
bash bin/stackalign version
bash bin/stackalign help
bash bin/stackalign doctor
```

### Plan the LEMP bootstrap

On a disposable supported EL9 VM:

```bash
sudo bash bin/stackalign install
```

Review the plan and the [LEMP beta guide](docs/LEMP-BETA.md) before considering apply. Apply is explicitly mutating:

```bash
sudo bash bin/stackalign install --apply
```

The apply path requires root and gates the host to EL9 x86_64. It installs the distro packages, configures the PHP-FPM www pool and an Nginx site, validates the generated configurations, then enables/starts the services. Package installation is not rolled back automatically if a later step fails; consult the guide for exact recovery limitations.

The repository's top-level `install.sh` is a release bootstrapper and intentionally refuses to run until a release hash is pinned. The commands above invoke the checked-out CLI directly; they are not a signed release installation.

## Development and tests

Run the standard checks:

```bash
make lint
make headers
make test
```

- `make lint` runs `bash -n` across the shell files and runs ShellCheck when installed. If ShellCheck is absent, that fact is reported and the ShellCheck check is skipped.
- `make headers` checks the SPDX and author headers on the configured source/test/workflow files.
- `make test` runs every `tests/test_*.sh` suite and then `tests/test_tune_math.py`. It continues through the suites and returns failure if any suite fails.
- `make all` runs lint, header checks, and tests.

### Optional test timing

The canonical `make test` recipe and its discovery/order remain unchanged. To measure total test-suite wall time, use the additive target:

```bash
make test-timed
```

The timing helper can also report selected command durations in the OpenSSH integration test:

```bash
STACKALIGN_TIMING=1 make test
```

When timing is disabled, wrapped commands run directly without clock subprocesses. If nanosecond clock support is unavailable, instrumentation falls back to ordinary command execution; the wrapper preserves command output and exit status. The overall timer uses Bash's coarse `SECONDS` counter when GNU nanosecond timestamps are unavailable.

Timing output is diagnostic only. No test is skipped, reordered, parallelized, or replaced by this instrumentation. No performance improvement is claimed until timings have been collected and compared on equivalent environments.

### CI

The repository's CI workflows exercise Ubuntu and AlmaLinux 9. Treat a CI result as evidence only for the exact commit and checks that actually ran. CI does not establish successful installation, real firewall behavior, real package transactions, recovery, security, or production readiness.

## Important limits and open validation

The following are not established as complete production workflows:

- Public web ingress, TLS issuance/renewal, DNS, and production firewall configuration.
- Application database/user provisioning, tenant management/isolation, and backups.
- Unattended updates or self-update.
- A release installer integrated with the release-signature verifier.
- Real-host package update transactions, service recovery, and rollback.
- Real-host egress firewall behavior, persistence, or network recovery.
- Live CentOS conversion, Oracle repository access, reboot, and post-update service validation.
- Production SFTP deployment and chroot isolation on a disposable target host.
- Measured PHP-FPM worker sizing or validated performance claims.

The `tested_matrix` values in `vendor/versions.toml` are empty and do not define a supported host matrix. Package-cache tests use fake package tools; they do not establish repository/signing-key behavior on a real machine.

Memory sizing is not yet a measured capacity guarantee. `SA_PHP_CHILD_MIB=30` and fixed service costs are provisional assumptions. The 512 MiB no-swap case has been checked arithmetically, not load-tested on a real 512 MiB VM. The `m2b/measure-php-child-rss.sh` helper collects measurements but its existence is not measurement evidence.

Use these evidence terms consistently:

- **PASS** — the named check ran and passed on the stated commit/environment.
- **FAIL** — the named check ran and failed.
- **NOT RUN** — no result exists.
- **UNVERIFIED** — the behavior has not been established by the required evidence.

A source file, design note, mock test, CI result, or successful plan does not prove real-host behavior.

## Documentation

- [LEMP beta bootstrap](docs/LEMP-BETA.md) — supported scope, apply behavior, recovery limitations, and host-validation checklist.
- [Egress firewall and passive LAN audit](docs/EGRESS.md) — opt-in nftables rules and read-only neighbour-cache audit.
- [Oracle Linux migration and updates](docs/ORACLE-LINUX-MIGRATION.md) — guarded conversion and package-update workflow.
- [Release Artifact Trust](docs/RELEASE-TRUST.md) — detached-signature and artifact-verification design/implementation boundary.
- [TLS client design](docs/TLS-CLIENTS.md) — Certbot, acme.sh, and Lego lineage ownership; design document, not runtime orchestration.
- [Technical Manual](docs/Technical%20Manual.md) — operational boundaries and policy notes.
- [Security Architecture Comparison](docs/SECURITY-ARCHITECTURE-COMPARISON.md) — package trust, lifecycle, rollback, provenance, and acceptance policy.
- [Clean-room provenance audit](docs/design/clean-room-provenance-audit.md) — records incomplete provenance evidence and unresolved imported archive/document rights. It is not a finding that GPL code is present and is not a legal opinion.
- [Early Tester Call](docs/EARLY-TESTER-CALL.md) — safe testing and defect-reporting guidance.

The TLS, security architecture, and provenance documents contain design, policy, or audit conclusions; they must not be read as proof that every described control is implemented.

## Early testing and defect reports

Testing contributions and reproducible defect reports are welcome. Use disposable AlmaLinux 9 or Rocky Linux 9 VMs where EL-family behavior is required.

Include:

1. Distribution, release, kernel, and architecture.
2. VM/container type and whether the environment is disposable.
3. Exact command and relevant configuration (with secrets removed).
4. Complete output and exit status.
5. Expected versus observed behavior.
6. Minimal reproducible steps and whether the issue reproduces on a clean environment.

Never include passwords, tokens, private keys, production hostnames, or other secrets. Start with the [Early Tester Call](docs/EARLY-TESTER-CALL.md).

## Project scope and contribution workflow

- Intended deployment scope: EL-family Linux on x86_64. Ubuntu is currently a CI platform, not a supported LEMP deployment target.
- Installer/runtime code is Bash. Python is used for development-time tests and measurement helpers.
- Package operations use DNF/YUM and upstream distribution packages; StackAlign does not build replacement forks of Nginx, PHP, or MariaDB.
- Manual update application is distinct from unattended/self-update behavior.
- Keep changes on focused branches and submit pull requests.
- Preserve existing history. Do not force-push or bypass review/CI protections.
- Do not describe a feature as complete until its implementation and required validation evidence are present.

## Oracle Linux legacy migration

`bash bin/stackalign-oracle` provides a guarded CentOS 7/8-to-Oracle Linux conversion wrapper and an Oracle Linux 7/8 package-update wrapper. Conversion requires an operator-provided Oracle `centos2ol.sh`, an independently checked SHA-256, a restorable snapshot, and explicit destructive-operation acknowledgement. Package updates are accepted only after the host identifies as Oracle Linux and every enabled repository explicitly has `gpgcheck=1`.

This wrapper has fake-tool unit coverage only. Live CentOS conversion, Oracle repository access, reboot, and post-update service validation remain **NOT RUN / UNVERIFIED**. Public YUM availability is not an Oracle Extended Support entitlement or an ELS security SLA. See [Oracle Linux migration and updates](docs/ORACLE-LINUX-MIGRATION.md).

## License

MIT. See [LICENSE](LICENSE).
