# First StackAlign production server acceptance

**Target:** one EL9 x86_64 host, one administrator-controlled application/site, Nginx + PHP-FPM + local MariaDB. This is not the multi-independent-customer hosting profile.

**Current status: NOT PRODUCTION-READY.** The current installer is a loopback-only baseline. This document is an acceptance contract, not evidence that any gate has passed.

## Deployment contract

- Supported operating systems are AlmaLinux 9, Rocky Linux 9, RHEL 9, Oracle Linux 9, and CentOS Stream 9 on x86_64, subject to exact package and kernel validation on each claimed distribution.
- Packages come from configured, signature-verified distribution repositories. No third-party repository is silently added.
- Nginx is the public HTTP/TLS edge only after TLS, firewall, and external reachability gates pass.
- PHP-FPM runs the one explicitly selected application identity. This single-site profile makes no multi-tenant isolation claim.
- MariaDB is local-only. Applications use a dedicated database and least-privilege application account; root/admin credentials are never embedded in the site tree or process arguments.
- All mutating commands require explicit apply and show their target paths, package changes, service actions, and recovery limits before mutation.

## Mandatory production gates

| Gate | Required evidence | Current state |
|---|---|---|
| Supported-host install | Clean disposable AlmaLinux 9 and Rocky Linux 9 VM installs; exact package versions, service states, and reboot persistence recorded | NOT RUN |
| Safe configuration deployment | Atomic writes, symlink/path refusal, full snapshot/restore of every managed path, failure injection at each write and service action | Partial implementation; CI pending |
| SELinux | Enforcing mode; correct labels for document root, PHP-FPM socket, logs, and any writable app paths; HTTP/PHP requests succeed without broad policy exceptions | NOT RUN |
| Network edge | Explicit HTTP/HTTPS ingress only; SSH management preserved; firewalld/nftables backend detected and one backend owned; external port scan confirms expected exposure | NOT IMPLEMENTED / NOT RUN |
| TLS | ACME issuance and renewal using protected credential transport, staged cert/key validation, atomic activation, rollback, timer ownership, and expiry monitoring | BLOCKED |
| Nginx/PHP | Effective config inspection, hidden-file denial, PHP execution, upload limits, error logging, version disclosure disabled, health check and graceful reload/recovery | Mock-tested only |
| Database | Local-only listener verified; root/admin auth hardened; dedicated app DB/user/grants; credential rotation and revocation; no remote TCP exposure | Partial; app user/grants NOT IMPLEMENTED |
| Backups | Encrypted backup, retention, off-host copy, integrity checks, isolated restore drill with application-level validation and measured RPO/RTO | Backup creation partial; restore NOT IMPLEMENTED |
| Updates | DNF transaction plan, configuration snapshot, service health checks, tested rollback/recovery, security update policy and maintenance window | Mock-tested only |
| Monitoring | Disk/inode, memory, CPU, service health, TLS expiry, DB health, backup age, and alert delivery tested | NOT IMPLEMENTED |
| Release trust | Versioned artifact, signed metadata, independently provisioned trust anchor, anti-rollback integration, reproducible release evidence | Verification helper exists; installer integration NOT IMPLEMENTED |
| Recovery | Reboot test, service restart test, backup restore, documented console recovery, and operator runbook | NOT RUN |

## Stop conditions

Do not expose the server publicly or place production data on it while any mandatory gate is BLOCKED, NOT IMPLEMENTED, or NOT RUN. Do not disable SELinux, flush an existing firewall, overwrite unknown configuration, or assume an SSH port without checking the live host. Never run destructive recovery tests against the only copy of real data.

## Evidence rules

A mock test proves only the mocked behavior. CI proves only the checks run against the exact commit and CI images. Production acceptance requires disposable real EL9 VMs and an operator-controlled staging deployment. Record exact commit SHA, OS image, kernel, package NEVRAs, commands, logs, before/after service state, and test outcome for each gate.

A first production server is accepted only when all mandatory gates have PASS evidence for the exact release candidate. Until then the accurate status remains **NOT PRODUCTION-READY**.
