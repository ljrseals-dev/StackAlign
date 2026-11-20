# StackAlign

**A guarded Bash toolkit for Linux host inspection and carefully gated administration.**

StackAlign is an experimental project for EL-family Linux systems. It provides a command-line interface, shell modules, tests, and operational documentation. Its current scope is intentionally conservative: inspect first, produce plans before changes, and keep high-risk operations blocked until their safety and recovery contracts are implemented and validated.

> [!WARNING]
> **Experimental beta — not production-ready.** Use disposable virtual machines or containers only. Do not run this project on production hosts or systems containing important data or real credentials. Passing unit tests or CI does not establish safe real-host operation.

## Safety principles

- Mutating workflows require explicit opt-in where implemented; plan/read-only modes are preferred.
- No hidden telemetry, remote configuration, or automatic network bootstrap.
- Secrets must not be committed, logged, or passed in process arguments.
- Preserve repository history. Use focused branches and pull requests; do not force-push.
- Distinguish implemented behavior, mock-test coverage, CI evidence, and real-host acceptance.
- Block destructive or security-sensitive workflows when prerequisites and rollback guarantees are absent.

## Current capabilities

| Area | Current state | Important limitation |
|---|---|---|
| CLI and host diagnostics | Version/help, read-only doctor, planning, and subsystem commands | Some recognized commands remain stubs or explicitly gated. |
| EL9 LEMP bootstrap | Plan/apply path for distribution-packaged Nginx, MariaDB, and PHP-FPM | EL9 x86_64 scope; experimental and not production-validated. |
| Hosting and vhosts | Read-only Nginx/Apache inventory and diagnostics; hosting plans | Site lifecycle and independent-tenant isolation remain gated. |
| Database | Read-only inventory and guarded database creation | User grants and destructive drop are not implemented. |
| Backups | Logical/physical backup creation, listing, and limited artifact checks | Restore, encryption, retention, off-host replication, and disaster recovery remain gated. |
| TLS | Read-only certificate status, client inventory, and renewal-scheduler preflight | Issuance, renewal, migration, and scheduler activation remain blocked. |
| Credential preflight | MySQL defaults-file checks require an absolute canonical path, regular non-symlink file, owner match, and mode 400 or 600 | Does not replace a real-host credential and recovery review. |
| Egress and SFTP | Guarded modules and fixture/integration test paths | Real-kernel firewall behavior and real-host SFTP acceptance remain unverified. |
| Oracle Linux migration | Guarded legacy conversion/update wrapper | Fake-tool tests only; live conversion and update have not been validated. |

The TLS clock gate requires `timedatectl` to report `NTPSynchronized=yes` before TLS preflight or Certbot HTTP-01 planning proceeds. It reports timezone separately and does not change system time, enable NTP, or modify timezone settings. See [TLS clock preflight](docs/TLS-CLOCK-PREFLIGHT.md).

TLS issuance and renewal remain blocked because protected secret transport, atomic certificate/key activation, crash recovery, scheduler isolation, and real-host acceptance are not yet established. A plan preview is not certificate issuance.

## Requirements

- Bash on GNU/Linux
- `make`
- Python 3 for the complete test suite
- EL9 x86_64 for the experimental LEMP apply path
- Root only for operations that explicitly require privileged apply

Ubuntu is used for CI; it is not currently a supported LEMP deployment target.

## Quick start

Inspect the CLI without applying changes:

```bash
bash bin/stackalign version
bash bin/stackalign help
bash bin/stackalign doctor
```

Inspect read-only plans:

```bash
bash bin/stackalign hosting plan nginx
bash bin/stackalign hosting plan apache
bash bin/stackalign hosting plan hybrid
bash bin/stackalign tls status
bash bin/stackalign tls preflight
```

The LEMP installer is plan-first. Review its output and [LEMP beta guide](docs/LEMP-BETA.md) before considering an explicitly mutating apply:

```bash
sudo bash bin/stackalign install
sudo bash bin/stackalign install --apply
```

Do not run apply on a production host.

## Database credential file

Database commands that need client credentials use a MySQL defaults file rather than a password argument. Set `SA_MYSQL_DEFAULTS_FILE` to an absolute canonical path. The file must be a regular readable non-symlink file, owned by the invoking effective user, with permissions `400` or `600`.

```bash
export SA_MYSQL_DEFAULTS_FILE=/etc/stackalign/mysql-admin.cnf
bash bin/stackalign db status
bash bin/stackalign db list
```

Keep the file outside the repository. Do not put credentials in shell history, command-line arguments, test output, or commits.

## Development and tests

Run the standard checks:

```bash
make lint
make headers
make test
```

- `make lint` runs Bash syntax checks and ShellCheck when installed.
- `make headers` checks configured SPDX/author headers.
- `make test` runs the shell test suites and Python tuning tests.
- A failure in any suite means the overall test run is not green.

CI workflows cover Ubuntu, AlmaLinux 9, and CentOS Stream 9 fixture environments. CI is revision-specific evidence, not proof of successful deployment, live package transactions, firewall behavior, recovery, or production readiness. Report checks as **PASS**, **FAIL**, **NOT RUN**, or **UNVERIFIED** and identify the exact commit/environment.

## Documentation

- [LEMP beta guide](docs/LEMP-BETA.md) — supported scope, apply behavior, and recovery limitations.
- [Beta hosting scope](docs/BETA-SCOPE-AND-HOSTING.md) — vhosts, hosting modes, and isolation boundaries.
- [Hosting modes](docs/HOSTING-MODES.md) — Nginx, Apache, and hybrid plans.
- [Internet access](docs/INTERNET-ACCESS.md) — access preferences and planning boundaries.
- [TLS client design](docs/TLS-CLIENTS.md) — client/lineage ownership and orchestration limits.
- [TLS clock preflight](docs/TLS-CLOCK-PREFLIGHT.md) — synchronized-clock gate and validation scope.
- [Egress controls](docs/EGRESS.md) — opt-in firewall policy and passive LAN inspection.
- [Release trust](docs/RELEASE-TRUST.md) — signature and artifact verification boundaries.
- [Oracle Linux migration](docs/ORACLE-LINUX-MIGRATION.md) — guarded legacy migration/update wrapper.
- [Security architecture comparison](docs/SECURITY-ARCHITECTURE-COMPARISON.md) — control and acceptance policy.
- [Clean-room provenance audit](docs/design/clean-room-provenance-audit.md) — outstanding provenance evidence; not a legal opinion.

## Contributing

Use a focused branch and submit a pull request. Preserve existing history; do not force-push or bypass review/CI protections. Include reproducible commands, full relevant output, exit status, OS/release/kernel/architecture, and whether the environment is disposable. Remove all credentials and sensitive host details from reports.

Do not describe a feature as complete until the implementation and required validation evidence are present.

## License

MIT. See [LICENSE](LICENSE).
