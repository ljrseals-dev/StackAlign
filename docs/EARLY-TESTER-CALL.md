# StackAlign: controlled pre-production beta

**Status: PRE-PRODUCTION BETA — NOT FOR PRODUCTION USE**

StackAlign is a Bash-based foundation for a planned LEMP deployment and management system targeting Enterprise Linux. This beta invites testers to inspect the current foundation, run checks in disposable environments, report defects, and submit focused pull requests.

**StackAlign does not install a complete Nginx, PHP-FPM, and MariaDB web stack.** This beta is not suitable for production hosts, business-critical workloads, or real credentials.

## Read before testing

- Read the [beta testing guide](BETA-TESTING.md) for the safety rules, suggested test session, evidence labels, and beta exit criteria.
- Read [CONTRIBUTING.md](../CONTRIBUTING.md) before opening a PR.
- Read the [Technical Manual](Technical%20Manual.md) for documented behavior and its verification status.
- Use disposable AlmaLinux 9 or Rocky Linux 9 VMs/containers only. Ubuntu 24.04 is used in CI, not declared as a deployment target.
- Do not expose test services to the public internet. Snapshot the environment before privileged or mutating tests.
- Never use real credentials or include passwords, tokens, private keys, session cookies, or sensitive host data in reports.

## What is in the current foundation

The exact source and tests on the commit you check out are authoritative. Current integrated areas include:

- Core CLI and foundation commands, configuration/rendering/history/service/repository helpers.
- Repository manifest pin parsing and RPM cache signature/NEVRA verification foundations.
- Manual update application and read-only update planning, with host transaction behavior still requiring disposable-host validation.
- Experimental operational library modules; these do not establish complete firewall, ACME, backup, antivirus, or daemon management workflows.
- Chrooted key-only SFTP management with disposable OpenSSH integration coverage in CI. Applying it changes system accounts and SSH configuration; only test in a disposable VM with console recovery.
- Memory-tuning arithmetic and tests; physical memory measurement and representative low-memory VM testing remain outstanding.

The installer intentionally refuses to run until a release hash is pinned. Do not expect a complete LEMP installation.

## Important limits

- Passing CI proves only that the named jobs passed on the tested commit. It is not real-host validation or a security certification.
- Package operations, service changes, rollback, SSH management, and other privileged paths must be treated according to their specific verification evidence.
- TLS runtime orchestration, certificate issuance/renewal, backups, firewall management, tenant isolation, and full LEMP provisioning are not established as complete workflows.
- The FTP policy allows ordinary authenticated client-to-server transfers through an independently managed server while specifying refusal of FTP-to-FTP third-party transfers (FXP). FXP software enforcement remains **unverified**; StackAlign does not install or manage the FTP daemon. FTPS behavior is separate.
- No performance, security, stability, recovery-time, or production-readiness claim is made.

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

Record the exact commit SHA, environment, commands, exit statuses, and relevant output. The doctor command inspects the host; run it only in a disposable environment.

## How to report feedback

Open a GitHub issue using the Bug Report or Feature Request form. Include the commit SHA, distribution/version, kernel, architecture, VM/container type, exact commands, expected and actual behavior, reproducible steps, and any system state that changed. Redact secrets and personal data.

For code or documentation changes, submit a focused PR against main. Run make lint and make test, add focused tests, update the Technical Manual where behavior changes, and complete the PR template. A maintainer review and passing required CI are expected before merge; opening a PR does not guarantee acceptance.

## Beta exit

This controlled beta remains open while the project completes supported-host integration testing, package trust verification, failure-injected rollback validation, security review, physical memory measurement, provenance review, and release-signing lifecycle work. See [BETA-TESTING.md](BETA-TESTING.md) for the full exit criteria.

Thank you for helping identify the gaps before StackAlign is considered for production use.
