# Configuration schema proposal

**Status: schema v1 validation implemented on a feature branch; no configuration is applied by validation.** `stackalign config validate [file]` checks this allowlist and its value/cross-field rules. Generic `sa_config_load` remains a parser; callers must invoke `sa_config_validate` explicitly.

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

## Version 1 validation contract

- Only the keys shown above are accepted. Unknown sections and keys are errors.
- `meta.config_version` is required and must equal `1`; `meta.allow_override`, when present, is `0` or `1`.
- Server role, tenant mode, PHP workload, Redis booleans/ports/memory/policies, site identity names, hostnames, resource limits, egress mode, and path syntax are validated.
- Every `site.<slug>` requires `domain`, `user`, `pool`, and `isolation=pool`. `free_for_all` accepts at most one site.
- Site resource limits are configuration values only. Validation does not create Unix users, PHP-FPM pools, cgroups, firewall rules, Redis instances, or filesystem boundaries.
- `php_version` is syntactically checked as major.minor; availability/support of that runtime is not checked.
- `sites_dir` and `open_basedir_extra` are syntax-checked, not created or resolved against the host filesystem.
- Validation does not write configuration, migrate old files, set defaults, or imply that a configuration is safe to apply to a live host.

See [ISOLATION.md](ISOLATION.md).
