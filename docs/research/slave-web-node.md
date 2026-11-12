# Slave-web node design

**Status: design only; implementation pending.** This document defines a proposed web-only LEMP node role. It does not claim that role support, tenant controls, or runtime isolation have been implemented.

## Role

slave_web is a disposable web worker behind a load balancer or DNS rotation. It runs Nginx and PHP-FPM tenant workloads. It does not host local MariaDB, mail, DNS, or a control panel by default. Database services are upstream/external unless explicitly configured otherwise.

This role is a key reason the tuner must accept service costs as input data: a web-only node must not reserve memory for a local MariaDB instance it does not run. The common tuning formula remains unchanged; the role supplies zero for absent local service costs. If Redis is external, local Redis memory cost is also zero. Locally running PHP-FPM workers and supervised application workers still consume local memory.

## Tenant model

The proposed default multi-tenant mode is pool: each site receives a distinct Unix account, PHP-FPM pool/socket, and private temp/session/upload/application-state directories. free_for_all shares identity and process context and is single-tenant only; it must never be represented as multi-tenant isolation.

The nine-layer design, actual enforcement mechanisms, and limitations are specified in [../ISOLATION.md](../ISOLATION.md). In particular, PHP-FPM pool names alone do not create per-site cgroups, open_basedir is PHP-level, and disable_functions is defense in depth rather than a kernel boundary.

## Proposed configuration shape

    [server]
    role=slave_web
    tenant_mode=pool
    sites_dir=/srv/sites

    [site.<slug>]
    domain=example.test
    user=site_<slug>
    pool=site_<slug>
    isolation=pool
    memory_max_mib=256
    cpu_quota_pct=100
    egress=loopback_db_only
    open_basedir_extra=
    php_version=8.3

This is a schema proposal only. Exact validation, path confinement, FPM process placement, firewall rules, and lifecycle behavior remain implementation work.

## Milestones

- M2a: role definition and design documentation.
- M2b: two live tenant tests for Layers 1–5, including pairwise/combinatorial cases. A config-only fixture is insufficient evidence.
- M3: site add/remove lifecycle commands.
- M4: cgroup v2 and systemd resource enforcement after choosing a verified FPM-to-cgroup architecture.
- M7: optional Landlock only after actual supported-kernel feature testing; chroot/namespaces remain per-site opt-ins subject to their own tests.
