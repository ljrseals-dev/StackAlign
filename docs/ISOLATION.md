# Slave-web tenant isolation contract

**Status: design only; implementation and two-live-tenant verification pending.** This document describes intended controls and their enforcement boundaries. It does not claim that any layer is implemented or that the stack has passed an isolation test.

## Node model

A slave_web node is a disposable web worker behind a load balancer or DNS rotation. It runs Nginx and PHP-FPM tenant workloads; it does not host local database, mail, DNS, or control-panel services by default. Database connectivity is to explicitly configured upstream services. The node is replaceable and should not be treated as a stateful control plane.

Two filesystem/identity modes are proposed:

- pool (default for multi-tenant nodes): distinct Unix user, FPM pool/socket, and private temporary, session, upload, and application-state directories per site.
- free_for_all: shared UID/pool/temp context; single-tenant only. It is not isolation. Refuse multi-site use, and explicitly refuse to describe shared www-data as multi-tenant isolation.

## Nine-layer defense-in-depth model

| Layer | Control | Enforced by | Boundary and limitations |
|---|---|---|---|
| 1 | Per-site Unix account and ownership | Linux DAC/UID/GID and filesystem permissions | Separates ordinary process access when ownership and permissions are correct; root and kernel compromise are outside this boundary. |
| 2 | Per-site PHP-FPM pool and socket | PHP-FPM pool configuration, Unix socket permissions, process credentials | Pool names alone do not create independent cgroups. A shared FPM master does not automatically give each pool independent systemd resource controls. |
| 3 | open_basedir | PHP runtime path checks | PHP-level restriction, not kernel confinement; not a substitute for filesystem permissions or namespaces. |
| 4 | Private temp, session, upload, and application-state directories | Filesystem ownership/permissions plus PHP-FPM pool settings | Requires distinct paths and correct ownership; do not use a shared writable temp/session directory in pool mode. |
| 5 | disable_functions denylist | PHP runtime function availability | Defense in depth only. It cannot disable language constructs such as eval, and it is not a complete shell-escape or syscall boundary. Application-specific exceptions must be explicit and audited. |
| 6 | Per-site memory/CPU limits | cgroup v2 kernel controllers | Requires an actual process-to-cgroup design. A pool stanza or slice name is not proof that FPM children are in that cgroup. |
| 7 | Service sandboxing | systemd unit sandbox directives and kernel enforcement | A drop-in on one shared FPM service is service-wide, not automatically per-site. Per-site enforcement needs one service instance per tenant or a tested delegation/migration design. |
| 8 | Egress restrictions | Kernel firewall (for example, nftables) with owner/cgroup-aware matching | Must distinguish TCP loopback from Unix-domain sockets; a Unix DB socket is not network egress. Rule ownership and bypass tests are required. |
| 9 | Request and abuse controls | Nginx rate limits and separately verified log-based controls such as fail2ban/CrowdSec | Primarily request-layer controls; they do not isolate tenant processes or filesystem access. Per-site attribution and log parsing require tests. |

No claim that layers 1–5 withstand a compromised plugin, or that the nine-layer contract is complete, is accepted without adversarial tests using two live tenants. Configuration text alone does not prove process separation, file isolation, egress restrictions, or resource enforcement.

## FPM-to-cgroup decision

Independent per-site cgroup enforcement requires one of:

1. one PHP-FPM service instance per site, each attached to its own systemd unit/slice; or
2. a documented and tested cgroup v2 delegation/migration design that reliably places every child process of each pool into its tenant cgroup.

The implementation must choose and test one model. Do not imply that naming a pool or declaring a slice creates the association.

## Optional stronger confinement

| Mechanism | Intended use | Gate |
|---|---|---|
| chroot | Optional per-site filesystem root, especially for selected untrusted PHP workloads | Must be per-site, never host-wide; verify required mounts, devices, paths, and operational behavior. |
| Linux namespaces | Optional mount/PID/network/user namespace separation where the workload requires it | Per-site only; verify kernel support, privilege model, lifecycle, and escape-resistance assumptions. |
| Landlock | Optional unprivileged filesystem access restriction | M7 only after feature-level tests on the actual supported AlmaLinux/Rocky kernels. Kernel version alone is not proof of required ABI/features. |
| CloudLinux CageFS/LVE | Optional vendor-specific tenant filesystem/resource controls | Only on a supported CloudLinux host and after validating vendor tooling/licensing. |

AlmaLinux 9's 5.14 kernel and AlmaLinux 10's expected newer kernel are not sufficient evidence by themselves. Landlock ABI and feature behavior must be probed and tested on actual target kernels before it is offered.

No host-wide chroot, namespaces, or Landlock policy is permitted as a shortcut for per-site isolation.

## Refusal and warning rules

- Refuse multi-site free_for_all; it is single-tenant only. Shared www-data is never multi-tenant isolation.
- Refuse security directives supplied through application-level php_value overrides.
- Do not configure shared /tmp as a writable tenant temp area in pool mode; use private per-site temp/session/upload paths.
- Pool mode with an empty disable_functions denylist should produce a prominent policy warning or fail the configured security profile, but the denylist must never be described as a kernel boundary.
- Do not claim per-site cgroup or systemd isolation until the process placement model is implemented and verified.
- Refuse host-wide chroot, namespace, or Landlock settings where the design requires per-site scope.
- Do not enable unprivileged user namespaces host-wide without an explicit kernel policy and tested threat model.
- Treat open_basedir and disable_functions as defense-in-depth controls, not substitutes for kernel enforcement.

## Milestone placement

- M2a: document the slave_web role and isolation design.
- M2b: implement/test Layers 1–5 with two live tenants and pairwise/combinatorial coverage.
- M3: site add/remove lifecycle commands.
- M4: cgroup v2 and systemd resource enforcement after the FPM-to-cgroup design is selected.
- M7: Landlock opt-in only after real-kernel feature verification.
