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


## Repair-branch implementation notes

The current security repair branch adds a narrow allowlisted command executor
(`lib/exec.sh`). It resolves selected system-management executables to fixed
absolute paths, passes arguments as distinct Bash array elements, starts them
with a minimal environment, and applies a timeout. It deliberately does not
log argument vectors. The executor is integrated into the CLI update planner,
LEMP package/service operations, repository package operations, database
clients, site diagnostics, secret helpers, and selected SFTP account/sshd
operations.

Shared semantic validators now cover package identifiers, database
identifiers, site slugs, DNS names, service names, ports, and canonical paths
beneath an approved root. The runtime INI parser accepts only the documented
version-1 `meta` and `security` keys and rejects unknown keys and invalid
types. Secret hash files are created through private same-directory temporary
files and atomic no-overwrite publication; secret generation disables
inherited xtrace inside its worker subshell.

These measures are not a complete command-execution migration. Other modules
still contain direct external-command calls and require individual review.
The executor currently streams command output rather than capturing and
redacting arbitrary child output; callers must not pass secrets in argv or
permit secrets to be emitted by child processes. The shell-level path checks
cannot eliminate every filesystem race; high-assurance operations need
directory-descriptor/openat-style implementations outside plain Bash.

Test fixture overrides are defined inside test scripts after sourcing the
production modules. Do not add a production environment variable that allows
arbitrary PATH-based executable substitution.

## Breaking and compatibility notes

- Unknown runtime configuration keys are now rejected. Only `meta.config_version`,
  `meta.allow_override`, `security.password_mode`, and
  `security.passphrase_wordlist` are accepted in schema version 1. The
  server/PHP/Redis/site examples in `docs/CONFIG-SCHEMA.md` remain proposals.
- The privileged CLI entrypoints use an absolute Bash interpreter in
  privileged mode and establish a predictable PATH before module dispatch.
- The update apply function now returns exit code 2 without invoking package
  or service tools. Update planning remains read-only and does not authorize
  apply.

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
