# Security policy

## Project status

StackAlign is an experimental beta Bash toolkit for EL-family Linux. It is
**not production-ready** and must not be run against production systems or
hosts containing valuable data. The project has not completed a comprehensive
security assessment or real-host acceptance testing.

## Threat model

The codebase manages privileged operating-system state: packages, services,
web-server configuration, databases, backups, firewall rules, and secrets.
Relevant threats include:

- command and argument injection through CLI, configuration, plan, or adapter data;
- PATH and environment-variable hijacking when invoked with elevated privileges;
- path traversal, symlink substitution, and time-of-check/time-of-use races;
- disclosure of credentials through arguments, logs, traces, temporary files,
  backups, or diagnostic output;
- malicious or compromised adapters, downloaded artifacts, repositories, and
  package metadata;
- partial system changes and failed recovery during package or service changes.

Bash quoting alone is not a complete trust boundary. Inputs must be validated
for the semantic domain in which they are used; commands should be invoked
with argument arrays and trusted executable paths; filesystem operations must
account for symlinks and concurrent changes.

## Mandatory feature gates

The following capabilities remain disabled or restricted:

- TLS issuance, renewal, and client migration;
- database DROP;
- site creation, removal, and tenant isolation;
- real-host DNF transaction rollback.

Do not bypass these gates by calling library functions directly. A plan is not
authorization to apply. Do not interpret a successful fixture test as
real-host acceptance evidence.

## Supported hardening practices

- Run tests and experiments only in disposable VMs or containers with
  snapshots and no production credentials.
- Keep ShellCheck and the repository test suite passing.
- Validate package, database, service, domain, and path inputs before use.
- Use private temporary directories and restrictive umasks for sensitive data.
- Never enable shell tracing around secrets.
- Keep repository signature verification enabled; SHA-256 alone proves byte
  identity, not publisher identity.
- Treat adapter output and plan files as untrusted data.
- Review every privileged operation and its failure/rollback behavior.

## Operational mitigations

1. Do not run StackAlign on production hosts.
2. Patch Apache, NGINX, MySQL/MariaDB, PHP, Ruby, and their dependencies using
   the distribution's supported security update process. StackAlign does not
   mitigate upstream server vulnerabilities.
3. Restrict administrative access and use a clean, known PATH and environment.
4. Keep secrets outside source control, shell arguments, command output, and
   world-readable files. Use dedicated least-privilege service accounts.
5. Test changes in disposable EL-family VMs, including interrupted operations
   and recovery paths.
6. Review package signatures, repository configuration, and artifact hashes
   independently before installation.
7. Keep backups offline or separately protected and verify restoration before
   relying on them.

## Reporting a vulnerability

Please do not publish exploitable details in a public issue. Contact the
maintainer privately through the GitHub repository owner's available security
contact channel. Include the affected revision, prerequisites, reproducible
steps, impact, and any proposed mitigation. Do not include real credentials,
private keys, or customer data in a report.
