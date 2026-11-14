# StackAlign controlled pre-production beta

**Status: PRE-PRODUCTION BETA — NOT FOR PRODUCTION USE**

This beta is intended to collect reproducible feedback, defects, and reviewed pull requests against a stable development baseline. It is not a production release and is not a complete LEMP installer.

## Scope of this beta

The repository contains a Bash-based CLI and a growing set of operational modules. Some functionality is tested with fake system tools; selected SFTP behavior also has disposable OpenSSH integration coverage in CI. The current source and tests are authoritative for what exists.

Important boundaries:

- StackAlign does **not** install a complete Nginx, PHP-FPM, and MariaDB web stack. The bootstrap installer refuses to proceed until its release hash is pinned.
- The memory-tuning work remains provisional. Physical worker-memory measurements and representative low-memory VM testing are outstanding.
- Package operations, service changes, rollback, and update behavior have not been validated end-to-end on production-like hosts.
- The release verifier is not yet integrated into the installer/update path.
- TLS orchestration, certificate issuance/renewal, backups, firewall management, tenant isolation, and other roadmap areas must not be treated as complete unless the current code and evidence demonstrate otherwise.
- FTP policy remains: StackAlign does not install or manage an FTP daemon; an independently managed server may be used. Ordinary authenticated client-to-server FTP is not to be indiscriminately blocked. Refusal of FTP-to-FTP third-party transfers (FXP) remains specified but **software enforcement is unverified**. FTPS behavior is separate and not established by that policy.
- SFTP management changes system users and OpenSSH configuration when applied. Test it only in a disposable VM/container with console access and a recovery path. Never risk locking yourself out of a real host.

## Tester safety rules

1. Use disposable AlmaLinux 9 or Rocky Linux 9 VMs/containers only. Ubuntu is a CI environment, not a declared deployment target.
2. Do not use production hosts, valuable data, real credentials, or private keys.
3. Do not expose SSH, FTP, web, or database services to the public internet for beta testing.
4. Take a disposable snapshot before testing commands that can mutate system state.
5. Review a command's plan and source before any apply operation. A plan is not proof that the apply path is safe.
6. Do not run privileged apply operations unless the test specifically requires them and the environment can be destroyed afterward.
7. Redact passwords, tokens, private keys, session cookies, public IPs if sensitive, and personal data from reports.
8. Stop if a command proposes an unexpected package, account, service, permission, firewall, or network change.

## Suggested first test session

From a fresh disposable checkout:

```bash
git rev-parse HEAD
make lint
make test
./bin/stackalign version
./bin/stackalign help
./bin/stackalign doctor
```

Record the exact commit SHA and environment. The doctor command may inspect the host; use only a disposable environment. Do not run install.sh expecting a complete web stack—the current installer intentionally refuses without a pinned release hash.

For SFTP, first inspect the implementation, CLI help, and tests. The CI integration test validates generated OpenSSH policy and a local chrooted transfer in a disposable test environment; it is not a production-host certification. Do not test the SFTP apply command on a host you need.

## What to include in feedback

- StackAlign commit SHA
- Distribution and exact version, kernel, architecture
- VM/container platform and resource limits
- Exact command line and exit status
- Complete relevant stdout/stderr, with secrets removed
- Expected versus actual behavior
- Reproduction steps and whether the issue is repeatable
- Any files, accounts, packages, services, or network settings changed
- Whether the issue also reproduces on a clean disposable environment

Open a GitHub issue using the Bug Report form. For a proposed fix, follow CONTRIBUTING.md and submit a focused PR.

## Evidence labels

Use these terms precisely:

- **PASS** — the named check ran and passed on the stated commit and environment.
- **FAIL** — the named check ran and failed.
- **NOT RUN** — no result exists.
- **UNVERIFIED** — behavior or implementation has not been established by the required evidence.
- **SPECIFIED** — documented design/policy; not proof of implementation.

A CI pass proves only that the named CI jobs passed on that commit. It does not establish installation success, security, isolation, reliability, performance, recovery, or production readiness.

## Beta exit criteria

The project may move beyond this controlled beta only after maintainers review and record evidence for, at minimum:

- A documented supported host matrix and clean install/upgrade/uninstall lifecycle.
- Successful disposable-host integration testing on each declared EL target.
- Verified package-source and signing-key trust behavior.
- Failure-injected transaction and rollback tests, including service health checks.
- Security review of privileged paths, secrets, account management, SSH policy, and network exposure.
- Physical memory measurements and representative load testing for published tuning guidance.
- A completed provenance review and accurate third-party notices.
- A release process with verified artifacts, checksums, signed tags, and documented key lifecycle.
- Updated Technical Manual and README that match the code and captured evidence.

These are exit criteria, not claims that the work is already complete.
