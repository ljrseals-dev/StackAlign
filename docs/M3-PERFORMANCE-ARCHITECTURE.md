# M3 Performance Architecture Contract

**Status: architecture and read-only planning stage. No production optimizer is implemented.**

StackAlign's performance work is a separate M3 feature. It must not be mixed into the TLS orchestration branch or the DNF package-transaction work.

## Operating contract

1. **One memory authority.** The optimizer delegates sizing to `lib/tune.sh`; it must not duplicate its arithmetic or derive worker counts independently.
2. **Plan before apply.** The first implementation exposes a read-only plan. It does not write sysctl, Nginx, PHP-FPM, MariaDB, or Redis configuration and does not install packages or restart services.
3. **Measured assumptions remain assumptions.** The current tuner defaults (including PHP child RSS) are provisional. A successful arithmetic plan is not proof that a host can safely sustain the proposed concurrency.
4. **Standard and super are explicit policies.** Standard is the conservative path. Super is opt-in and may propose static PHP-FPM only after measured worker PSS/RSS and a complete memory budget support it.
5. **No silent durability downgrade.** MariaDB `innodb_flush_log_at_trx_commit=2` is not a generic speed switch. Super mode must disclose the possible loss of recent committed transactions after a crash/power loss and require explicit operator acknowledgement before any future apply implementation.
6. **Capability checks precede kernel changes.** BBR, qdisc, sysctl keys, service unit capabilities, and file-descriptor limits must be detected. Unsupported optional tuning is reported, not blindly applied.
7. **Transactional apply.** A future apply path must snapshot every changed file, record package/service state, validate all rendered configs before reload, health-check each service, and restore the prior state on failure. A snapshot of `/etc` alone is not a complete package transaction.

## Nginx and cache policy

Future FastCGI microcaching is opt-in per site/workload, not a universal PHP cache. The cache key must include the scheme, host, request method, URI, and arguments where relevant. Cache bypass and no-cache-write rules must be paired.

At minimum, bypass both lookup and cache write for:
- AI crawler user agents configured by the operator;
- POST and other non-safe methods;
- non-empty Authorization headers;
- logged-in, session, comment-author, and application-specific authentication cookies;
- application routes known to be personalized or transactional.

Do not ignore upstream `Set-Cookie`, `Cache-Control`, or `Expires` headers merely to force caching. Responses carrying cookies or private/no-store policy must not enter the shared cache. Keep HTTP conditional request semantics intact; do not strip ETag/If-Modified-Since or manufacture 200 responses as a crawler workaround.

AI user-agent matching is a cache policy signal, not identity verification. Spoofing is possible. IP verification, if later implemented, belongs in a separately reviewed network/firewall feature.

## Workload layers

- **Nginx:** microcache, cache locking, Brotli/HTTP/3 only when the installed build supports the required modules/protocols.
- **PHP-FPM:** dynamic is the general candidate; ondemand for constrained/low-traffic systems; static only for measured sustained workloads whose fixed worker budget fits.
- **OPcache:** enable and size within the tuner budget. JIT is workload-specific and must be benchmarked rather than assumed beneficial for typical PHP request workloads.
- **MariaDB:** buffer pool comes from the tuner. Connection limits must account for PHP and worker connection budgets. Do not assume a universal percentage of RAM.
- **Redis:** opt-in, isolated, loopback-bound by default, memory-capped, and integrated only for a supported application/plugin. Object cache and session storage are distinct features.
- **Kernel:** conservative, capability-checked settings only; no universal TCP buffer/backlog values presented as a guaranteed throughput improvement.

## Current implementation

`lib/optimize.sh` currently provides `sa_optimize_plan standard|super`. It reads host memory facts, invokes the existing tuner as a separate process, validates required key/value output, and prints a plan. It does not mutate the host.

CLI:
```bash
stackalign optimize --plan
stackalign optimize super --plan
```

The `--apply` path is intentionally not implemented in this PR. Future work requires the measured M2b memory gate, Nginx template/render integration, service transaction design, package dependency policy, and failure-injection tests before enabling mutation.

## Acceptance gates for apply

- No duplicate memory arithmetic and no malformed/missing tuner fields accepted.
- Measured PHP worker memory for each supported workload.
- Cache isolation tests for anonymous, authenticated, cookie-bearing, Authorization, POST, Set-Cookie, private/no-store, and AI-UA requests.
- Nginx config validation and PHP-FPM/MariaDB validation before any reload.
- BBR/qdisc/sysctl capability tests and explicit fallback reporting.
- Rollback tests for every file and service failure point.
- Repeatable load benchmarks with baseline and optimized results; no “10x” or “peak performance” claims without measured evidence.
