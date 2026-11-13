# StackAlign

An early-stage Bash-based foundation for a pre-tuned LEMP (Nginx, MariaDB, PHP-FPM) installer and manager, targeting EL-family x86_64 servers.

**StackAlign does not install a web stack yet. It is not production-ready.**

## Project status — 12 November 2026

StackAlign is an experimental foundation intended for review and disposable-environment testing. The project follows one rule: **measure, do not claim**.

- The CLI includes `version`, `help`, `plan`, `doctor`, `rollback`, and `secret gen/list`. These features have been tested locally; independent host validation is still needed.
- Library modules cover configuration, rendering, history, service, repository, and secret handling. Their local tests use fakes and do not establish behavior against live services.
- `lib/tune.sh` is provisional. The lean profile is available; the standard profile refuses. Its memory assumptions have not been validated against physical measurements.
- `install.sh` refuses to run by design until a release hash is pinned.
- Nginx, PHP-FPM, and MariaDB installation is not built.
- Templates, TLS, backups, firewall management, and tenant management are not built.

GitHub Actions CI has run on Ubuntu 24.04 and AlmaLinux 9 for earlier revisions, including lint and test jobs. CI results are not real-host installation or runtime validation. Check the current [main-branch workflow runs](https://github.com/ljrseals-dev/StackAlign/actions?query=branch%3Amain) for the latest status.

## Early testers wanted

We welcome people who want to inspect the foundation, run its checks, and report defects.

**Safety requirements:**

- Use disposable containers or virtual machines only.
- Prefer throwaway AlmaLinux 9 or Rocky Linux 9 environments for EL-family testing.
- Never run StackAlign on a machine that matters or with real credentials.
- Do not use production systems or important data.
- Redact passwords, tokens, private keys, and other secrets from all reports.

Start with the [Early Tester Call](docs/EARLY-TESTER-CALL.md). Report the distribution and version, kernel, architecture, VM/container type, exact commands, complete output, failures, and reproducible steps.

## Memory tuning and measurement status

The M2a arithmetic implementation and contract tests are present. The current pinned test floors are T27 = 391 MiB and T28 = 3389 MiB.

The M2b measurement gate remains open:

- `SA_PHP_CHILD_MIB=30` is a provisional assumption, not a measured worker footprint.
- Fixed service costs are also assumptions pending representative host measurements.
- The 512 MiB no-swap case has been checked arithmetically, not load-tested on a real 512 MiB VM.
- `m2b/measure-php-child-rss.sh` is provided to collect PHP-FPM worker PSS under baseline and heavier workloads. Its output must be collected on a real test host; it is not evidence until actually run.
- Do not change the tuning assumptions or claim M2b completion without reviewing the physical measurements.

No measured sizing table or performance, security, stability, or recovery-time claim is published.

## Scope and operating principles

- Intended deployment scope: EL-family Linux on x86_64. Ubuntu 24.04 is used as a CI environment, not currently a supported deployment target.
- Bash for installer and runtime code. Python is used for development-time tests and benchmarks.
- No unattended update application.
- No secrets in the repository, logs, snapshots, or Git history.
- No telemetry, network bootstrap, or hidden remote configuration.
- Keep measured results, CI results, and design assumptions clearly distinguished.

## Development

Use focused feature branches and pull requests. Preserve existing history and never force-push. Keep `main` protected from unreviewed changes. A merge or passing CI job is not evidence of successful installation or production operation.

## License

MIT. See [LICENSE](LICENSE).
