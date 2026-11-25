# phpMyAdmin Integration — Stage A Audit and Stage B Design

**Repository:** ljrseals-dev/StackAlign  
**Audit base:** main @ `cb141ee32f33d5ec8ab8da146c6aacd1d69f1e58`  
**Audit date:** 2026-11-25  
**Status:** AUDIT AUTHORED; no host deployment or real-host acceptance performed

## Scope and evidence

The audit inspected the repository tree, `lib/db.sh`, `bin/stackalign` database dispatch, `tests/test_db.sh`, `tests/test_db_cli.sh`, `lib/backup.sh`, `lib/lemp.sh`, `lib/exec.sh`, `lib/service.sh`, `lib/history.sh`, `lib/config.sh`, `Makefile`, and README.

Repository source was fetched from GitHub. No local checkout/build environment was available in this audit; no test command was executed. CI evidence remains fixture-based and must not be treated as live-host acceptance.

## Current verified state

### Database CLI and helper

- `lib/db.sh` supports read-only status, database listing, user/host listing, guarded database creation, and a blocked drop operation.
- MySQL client selection is centralized in `lib/exec.sh`: it uses `/usr/bin/mysql` when present, otherwise `/usr/bin/mariadb`.
- Database credential-file validation requires a canonical absolute regular non-symlink file, readable by the caller, owned by the caller, and mode 0400 or 0600. The path is supplied by `SA_MYSQL_DEFAULTS_FILE`.
- The status query returns server version and authenticated account; the database list and user list are read-only.
- Database creation is plan-first at CLI level, validates database names, and is idempotent.
- Database drop is deliberately blocked.
- Existing database tests use fake client fixtures and do not contact a live server.

### Web stack / installer

- `lib/lemp.sh` is an EL9 x86_64 beta installer for distribution packages (Nginx, MariaDB, PHP-FPM, php-mysqlnd).
- Its stated scope is a loopback HTTP endpoint on 127.0.0.1:8080, MariaDB bound to 127.0.0.1, and local socket access.
- The LEMP apply path installs and configures MariaDB; it does **not** first reconcile an existing Oracle MySQL/MariaDB service or prove application database dependencies. phpMyAdmin must not call this installer as an implicit prerequisite.
- Current installer scope excludes TLS, public DNS, firewall rules, database/user provisioning, tenant isolation, backups, and production hardening.

### Backups and recovery

- `lib/backup.sh` implements guarded logical all-database gzip dumps and MariaBackup physical backups, with listing and limited integrity checks.
- Logical verification checks gzip container integrity only; SQL semantics and restoreability are not verified.
- Existing documentation says restore, encryption, retention, off-host replication, and disaster recovery are gated/incomplete.
- No evidence in the inspected code establishes encrypted off-host backup, automatic daily backup, isolated weekly restore tests, or tested application recovery.

### Safety primitives

- `lib/exec.sh` has an allowlisted command execution boundary and timeout/captured-output helpers.
- `lib/history.sh` provides path snapshots and rollback for supported file mutations, with private history requirements.
- `lib/service.sh` has safe reload/rollback logic for supported services.
- These are building blocks, not an existing phpMyAdmin installer, auth gateway, advisory monitor, or deployment rollback implementation.

## Gaps against the requested feature

| Requirement | Source audit result |
|---|---|
| phpMyAdmin installer | NOT IMPLEMENTED in inspected CLI/modules |
| Verified upstream artifact install | NOT IMPLEMENTED for phpMyAdmin |
| Server-side auth gateway / MFA | NOT IMPLEMENTED for phpMyAdmin |
| Protected route and bypass audit | NOT IMPLEMENTED for phpMyAdmin |
| MySQL/MariaDB endpoint discovery | PARTIAL; status relies on client defaults-file, endpoint/socket is not inventoried |
| Application-to-database dependency inventory | NOT IMPLEMENTED |
| Multiple approved database targets | NOT IMPLEMENTED |
| DB connection alignment / doctor | NOT IMPLEMENTED |
| DB grant/security inventory | PARTIAL; user/host inventory exists, grants not audited |
| Four-hour advisory scheduler | NOT IMPLEMENTED for phpMyAdmin |
| Upstream advisory/release correlation | NOT IMPLEMENTED |
| phpMyAdmin staged update/rollback | NOT IMPLEMENTED |
| Encrypted/off-host phpMyAdmin+DB backup | NOT VERIFIED / NOT IMPLEMENTED as an integrated workflow |
| Isolated restore tests | NOT IMPLEMENTED |
| Lockdown/recovery for phpMyAdmin | NOT IMPLEMENTED |
| Tests | Existing DB helper/CLI fixture tests; new feature tests NOT IMPLEMENTED |
| Real-host acceptance | NOT RUN |

## Design decisions / boundaries

1. **Do not make phpMyAdmin install depend on `stackalign install`.** The LEMP bootstrap can provision MariaDB and change host services; phpMyAdmin integration must first inspect/reuse the actual database server and never install a second engine implicitly.
2. **Extend the existing DB subsystem.** Keep `lib/db.sh`, `stackalign db`, `SA_MYSQL_DEFAULTS_FILE`, and existing tests as the authoritative database helper/credential conventions. Avoid creating a second DB command namespace or credential store.
3. **Treat endpoints as explicit approved targets.** Discovery must be read-only and report confidence (CONFIRMED / UNKNOWN); do not infer endpoints from secrets or blindly assume localhost/socket.
4. **Separate application and portal authentication.** Database account credentials remain independent from web gateway identity; phpMyAdmin uses cookie authentication. An existing trusted server-side gate must be used or installation is blocked.
5. **Plan-first and narrow impact.** Install/update/firewall/config/lockdown mutations require plan output, explicit apply, snapshots, bounded service reloads, and safe rollback. phpMyAdmin failures must not stop MySQL/MariaDB or other applications.
6. **Security-source failure is degraded.** Advisory source failure or stale data must not be represented as a clean scan.
7. **Restore proof is separate from backup creation.** A dump file or gzip check is not proof of recoverability; restore testing must be isolated.

## Proposed phased implementation

### Phase 1 — DB alignment diagnostics (read-only)
- Add DB endpoint and engine diagnostics with safe structured output.
- Add application-to-database discovery adapters only for known, documented config formats; never source application config or print secret values.
- Add `stackalign db connections`, `applications`, `doctor`, and `security-check` as read-only commands only after CLI compatibility and tests are established.
- Unknown dependencies are reported UNKNOWN. Do not make repairs automatically.

### Phase 2 — Protected phpMyAdmin plan/preflight
- Add phpMyAdmin plan/status/preflight commands.
- Preflight validates supported host, existing web stack, PHP compatibility/modules, approved DB target, route/auth gate availability, TLS prerequisites, safe directories, artifact verification capabilities, and backup availability.
- If a supported trusted auth gateway/MFA path is unavailable, fail closed and keep portal uninstalled/disabled.
- Do not use the LEMP bootstrap to provision a database as a side effect.

### Phase 3 — Installer and protection
- Verify upstream release/signatures through an explicit trust model; staged extraction validates archive paths and symlink entries before extraction.
- Dedicated read-only application tree, private config/session/temp/upload storage.
- Cookie auth, generated cookie secret, approved target allowlist, protected HTTPS route, no direct/bypass route, validated server configuration, safe reload and rollback.
- Preserve existing application routes and database endpoint.

### Phase 4 — Monitoring, controlled update, backups and recovery
- Four-hour systemd monitor only after scheduler architecture, service ownership, and test contract are reviewed.
- Advisory sources have freshness and failure states; no remote data is executable.
- Staged updates, pre-update backup, integrity/compatibility checks, health checks and verified rollback.
- Encryption/off-host backup requires an explicit operator-configured destination and key management; no credentials embedded.
- Weekly isolated restore tests must never use production destinations.

### Phase 5 — Test, security review, PR
- Add fixture-based tests for endpoint detection, unknown config formats, redaction, spoofed gateway headers, route bypass, artifact authenticity/path traversal, scheduler state, advisory failures, update rollback, backup integrity and isolated restore safety.
- Run the repository test/lint/security/header targets only in an available environment. Record exact test output and commit SHA.
- Review changed files and PR diff for fail-open behavior, privilege boundaries, symlinks/races, secret leakage, and unintended service effects.

## Exact next source files likely to be changed (subject to Phase 1 findings)

- `lib/db.sh`
- `bin/stackalign`
- `tests/test_db.sh`
- `tests/test_db_cli.sh`
- new DB alignment discovery module (only if the existing DB module cannot safely host it)
- new phpMyAdmin module and focused tests
- `Makefile` only if test targets require it
- focused feature documentation under `docs/`

No files on `main` have been modified. No database, package, service, web-server, firewall, or host configuration has been changed.
