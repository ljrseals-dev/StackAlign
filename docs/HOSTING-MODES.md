# StackAlign hosting modes

**Status: mode contract and read-only planner implemented; apply is blocked.**

StackAlign defines three hosting modes:

| Mode | Edge | Application server | Intended use |
|---|---|---|---|
| `nginx` | Nginx | PHP-FPM | Existing default direction |
| `apache` | Apache HTTP Server | Apache + PHP-FPM | Apache compatibility |
| `hybrid` | Nginx | Apache + PHP-FPM | Nginx edge with Apache upstream |

## Safety boundary

The current `hosting plan` command is read-only. It does not install packages, write configuration, enable services, open firewall ports, or create tenants.

Apache and hybrid apply are blocked until the per-tenant identity, PHP-FPM, service and cgroup model has been implemented and verified. Apache-only mode is limited to single-tenant evaluation until that gate passes. A collection of virtual hosts is not proof of tenant isolation.

## Apache requirements

The intended EL-family package is the distribution's `httpd` package. Required module capabilities are:

- `mod_proxy`
- `mod_proxy_fcgi`
- `mpm_event`

PHP execution must use a dedicated PHP-FPM pool and socket. Do not attach Apache to the existing shared `www` pool and call that tenant isolation.

## Hybrid routing

The intended topology is:

1. Nginx owns the public listener and TLS termination.
2. Nginx proxies requests to Apache on `127.0.0.1:8081`.
3. Apache is not reachable from public interfaces.
4. Apache forwards PHP requests to a dedicated PHP-FPM pool.
5. Tenant-specific process and filesystem boundaries are enforced independently of vhost routing.

The backend address is a design default, not an active listener or a firewall guarantee.

## Operator scope selection

Before configuring hosting, run `stackalign hosting setup` from an interactive terminal. It asks whether the server is managed by one administrator across multiple accounts or is intended for multiple independent end users. The first choice is a single-admin scope, not a claim of per-account isolation. The second choice is explicitly blocked until independent-user isolation is implemented and adversarially tested. The current command reports the selection but does not persist it; durable scope configuration is not yet implemented.

## CLI

Read-only plans:

```bash
stackalign hosting plan nginx
stackalign hosting plan apache
stackalign hosting plan hybrid
stackalign hosting setup
```

Inspect installed server binaries and Apache proxy module availability:

```bash
stackalign hosting doctor [nginx|apache|hybrid]
```

No apply command is available yet. An attempted apply must fail closed rather than partially configuring a host.

## Acceptance gates before apply

- DNF package-source policy and package availability checked on supported EL9 hosts.
- Apache configuration passes `httpd -t`.
- Required modules are present and the selected MPM is verified.
- PHP-FPM uses a dedicated pool/socket with restrictive ownership.
- Hybrid Apache listener is verified loopback-only.
- Nginx and Apache health checks pass.
- Failure injection restores prior configuration and service state.
- Two-live-tenant adversarial tests prove filesystem, socket, process, resource and egress boundaries before multi-tenant support is claimed.

Until those checks run, Apache integration remains **PLANNED / APPLY BLOCKED / REAL-HOST VALIDATION NOT RUN**.
