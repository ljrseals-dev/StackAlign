# StackAlign controlled pre-production beta

**Status: PRE-PRODUCTION BETA — NOT FOR PRODUCTION USE**

This beta is intended to collect reproducible feedback, defects, and reviewed pull requests against a stable development baseline. It is not a production release and is not a complete LEMP installer.

## Scope of this beta

The repository contains a Bash-based CLI and a growing set of operational modules. Earlier draft PRs #10, #26, and #28 were closed unmerged; their work was superseded by later merged PRs #33, #38, and #37 respectively. The replacement PR heads passed Ubuntu and AlmaLinux 9 CI: #33 run [43557257210](https://github.com/ljrseals-dev/StackAlign/actions/runs/43557257210), #38 run [43557813317](https://github.com/ljrseals-dev/StackAlign/actions/runs/43557813317), and #37 run [43558218351](https://github.com/ljrseals-dev/StackAlign/actions/runs/43558218351). These results apply to those exact commits and do not prove production-host behavior.

Important boundaries:

- StackAlign does **not** install a complete Nginx, PHP-FPM, and MariaDB web stack. The bootstrap installer refuses to proceed until its release hash is pinned.
- The memory-tuning work remains provisional. Physical worker-memory measurements and representative low-memory VM testing are outstanding.
- **Update planning (#10):** the original draft PR #10 is closed unmerged, superseded by merged PR #33. PR #33 adds a distinct T36 read-only planning suite that checks exact current/target NEVRA output, cached-only DNF repoquery with the persistent logfile disabled, absence of StackAlign snapshot/cache/config state, and explicit scope/downtime/test-matrix disclosures. This covers the read-only planning path that was missing from #10. The tests use fake RPM/DNF tools; live DNF metadata behavior and real-host transaction safety remain unverified. Testers must not treat plan output as proof that apply is safe.
- **Operational modules / FTP package refusal (#26):** the original draft PR #26 is closed unmerged, superseded by merged PR #38. The replacement passed Ubuntu and AlmaLinux 9 CI. The package refusal applies only to StackAlign-managed FTP-daemon installation; an independently managed server and ordinary client-to-server FTP are not blocked by that guard. Daemon-level FXP enforcement remains unverified.
- **SFTP chroot (#28):** the original draft PR #28 is closed unmerged, superseded by merged PR #37. The replacement passed Ubuntu and AlmaLinux 9 CI and includes an actual OpenSSH integration test in disposable CI. The test sources StackAlign's real `lib/sftp.sh`, calls `sa_sftp_add_user()` to create the temporary per-user chroot and `sa_sftp_render()` to generate the Match policy, then runs real `sshd`, checks `sshd -t` and `sshd -T -C`, performs a key-authenticated SFTP transfer inside that chroot, and confirms an ordinary SSH shell login still works. This is real OpenSSH integration against a chroot produced by the SFTP library—not a synthetic hand-built chroot. It does not exercise the CLI `stackalign sftp add --apply` path or `sa_sftp_enable()` end-to-end, and it is not production-host certification.
- Package operations, service changes, rollback, and update behavior have not been validated end-to-end on production-like hosts.
- The release verifier is not yet integrated into the installer/update path.
- TLS orchestration, certificate issuance/renewal, backups, firewall management, tenant isolation, and other roadmap areas must not be treated as complete unless the current code and evidence demonstrate otherwise.
- **FTP policy and reconciliation (keep the layers distinct):** ordinary authenticated client-to-server FTP is allowed; FTP-to-FTP third-party transfers (FXP) are specified to be refused, but daemon-level enforcement is unverified; FTPS remains a separate unresolved policy/implementation question; and an externally managed FTP daemon is informational to `doctor`, not refused. PR #27 documents the policy, PR #32 changes the doctor classification, and PR #38 limits StackAlign's package refusal to StackAlign-managed FTP-daemon installation. StackAlign does not install or manage an external daemon. Do not describe FTP as simply “resolved” or claim FXP enforcement.
- **Provenance (#11):** the clean-room provenance audit remains **RISK DETECTED — provenance incomplete**. This is not a finding that GPL code is present and not a legal opinion.
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

For SFTP, first inspect the implementation, CLI help, and tests. PR #37's CI integration test sources `lib/sftp.sh`, calls `sa_sftp_add_user()` to create the temporary chroot and `sa_sftp_render()` to generate the Match policy, then validates the configuration with real OpenSSH (`sshd -t` and `sshd -T -C`), performs a key-authenticated SFTP transfer, and checks ordinary SSH shell login. This validates the library-generated chroot with real OpenSSH. It does not exercise the CLI `stackalign sftp add --apply` path or `sa_sftp_enable()` end-to-end, and it is not production-host certification. Do not test the SFTP apply command on a host you need.

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
