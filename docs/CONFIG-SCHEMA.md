# Configuration schema proposal

**Status: design only; parser and validation are not implemented.** This document specifies intended keys, not accepted runtime syntax.

## Server role

    [server]
    role=master_lemp
    tenant_mode=pool
    sites_dir=/srv/sites

Supported role values proposed here are master_lemp and slave_web. A slave_web node is web-only and normally has no local MariaDB. Local service costs are role/configuration inputs to the common tuner, not hardcoded role-specific formulas.

## PHP workload

    [php]
    workload=plain

Proposed workload values: plain, wordpress, laravel, xcart. Workload policy floors are advisory. The only hard sizing refusal is arithmetic infeasibility.

## Redis services

    [redis.sessions]
    enabled=false
    maxmemory_mib=32
    maxmemory_policy=noeviction
    port=6379

    [redis.cache]
    enabled=false
    maxmemory_mib=64
    maxmemory_policy=allkeys-lru
    port=6380

X-Cart's guarded workload defaults may enable both instances. These values are configured service costs, not optimization variables. Explicit user values override workload defaults. Disabled or externally hosted Redis has no local memory reservation.

## Slave-web tenants

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

The proposed server-level tenant_mode values are pool and free_for_all. pool means a distinct Unix user, PHP-FPM pool/socket, and private state directories per site. It does not, by itself, provide per-site cgroups or a kernel security boundary. free_for_all shares identity/pool/temp state and is single-tenant only; shared www-data is never multi-tenant isolation.

The exact accepted keys, defaults, types, path validation, and compatibility rules must be finalized with parser implementation and tests. See [ISOLATION.md](ISOLATION.md).
