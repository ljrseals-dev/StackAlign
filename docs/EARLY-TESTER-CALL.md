# StackAlign: Call for Early Testers

StackAlign is an early-stage, pre-tuned LEMP (Nginx, MariaDB, PHP-FPM) installer and manager for EL-family x86_64 servers. **It does not install a web stack yet.**

This call is for people who want to try the foundation and break it.

## Read this first

- **Containers or VMs only.** Never run it on a machine that matters, and never with real credentials. Use a throwaway AlmaLinux 9 or Rocky Linux 9 container or VM.
- **Nothing here is production-ready.** No performance, security, or stability claim is made. The project's rule is "measure, do not claim."
- **Do not treat CI as real-host validation.** GitHub Actions checks have passed on earlier commits, but that does not establish behavior on your host, prove the installer works end-to-end, or replace the pending 512 MiB VM measurements. Check the current main-branch workflow status before testing.

## What exists

The following is a snapshot of the project's scope, not a guarantee that every item is complete or production-ready. Check the repository and current CI status for the latest state.

| Area | State |
|---|---|
| CLI: version, help, plan, doctor, rollback, secret gen/list | Written; tests exist, but independent host validation is still needed |
| Library modules: config, render, history, service, repo, secret | Written; tests use fakes and do not prove behavior against live services |
| `lib/tune.sh` memory tuner | Provisional; lean profile only; standard profile refuses; not validated against physical memory measurements |
| `install.sh` | Refuses to run by design until a release hash is pinned |
| Nginx / PHP-FPM / MariaDB installation | Not built |
| Templates, TLS, backups, firewall, tenants | Not built |

## What we want tested

Use a disposable AlmaLinux 9 or Rocky Linux 9 environment. Review the current README and docs before running commands. Report:

- Distribution and version, kernel, architecture, and VM/container type
- Commands run and their complete output
- Failures, unexpected changes, and reproducible steps
- Whether any test touched files or services outside the disposable environment

Do not provide real passwords, tokens, private keys, or other credentials in reports.

## Important limits

- This is an early foundation, not a working LEMP installer.
- Do not use it on production systems or systems containing important data.
- Do not infer security, performance, or reliability from passing unit tests or CI.
- The M2b memory-measurement gate remains open. No physical measurement-based tuning claim is made.

## How to help

Open an issue with the environment details, exact commands, raw output, and a concise description of what happened. Redact secrets before posting logs.

Thanks for helping find the gaps before this project grows further.
