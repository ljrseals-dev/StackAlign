# StackAlign

A standalone Bash-based LEMP installer and manager for supported EL-family Linux systems on x86_64.

## Project status

**Repository initialized; implementation and validation are pending.** This README is the initial repository seed, not a claim that the installer, tuning engine, application profiles, or deployment workflows are complete.

## Scope

StackAlign is limited to managing a LEMP server stack and its supported self-hosted PHP application workloads. Hosted SaaS services are outside the scope of server-side tuning. Unrelated application domains and services are intentionally excluded.

Planned workload profiles include generic PHP, WordPress/WooCommerce, Laravel, and selected self-hosted applications. X-Cart 5.6 is treated as a guarded LEMP workload profile. Resource shortfalls should produce explicit warnings and sizing guidance; a policy recommendation such as a 2 GiB minimum is advisory and is not, by itself, an automatic deployment refusal.

## Operating principles

- Bash is the installer/runtime language. Python may be used for development tests and benchmarks only.
- Target EL-family x86_64 systems; supported distributions and versions must be pinned and tested explicitly.
- No unattended update application.
- No secrets in the repository, logs, snapshots, or Git history. Runtime secrets belong under `/etc/stackalign/secrets/` with restrictive permissions; snapshots exclude them by default.
- No network bootstrap, telemetry, or hidden remote configuration.
- No unmeasured performance, memory, or recovery-time claims.
- Keep all sizing formulas and sizing tables in `docs/TUNING.md`; generated tables must be reproduced by a checked script before publication.
- Clearly distinguish implemented, tested, untested, and blocked work.

## Development workflow

Work on short-lived feature branches, review changes through pull requests, and preserve `main`. Do not force-push. A merge is not evidence of a successful build, installation, or runtime validation.

## License

MIT. See [LICENSE](LICENSE).
