# TLS client integration — repository-first design

SPDX-License-Identifier: MIT
Author: Lewis James Seals Jr.

## Status

Design proposal only. No TLS runtime behavior is implemented by this document. No repository is enabled, no package is installed, and no certificate is issued by this change.

## Requirement

StackAlign targets AlmaLinux and Rocky Linux 9/10. TLS support reuses maintained ACME client projects; StackAlign does not implement the ACME protocol itself and does not bootstrap clients from the internet. StackAlign must not copy, vendor, fork, or translate an ACME client's implementation.

## Upstream projects

- Certbot: https://github.com/certbot/certbot
  - Let's Encrypt recommends Certbot as a starting client for many users.
  - On EL, Certbot is commonly supplied through EPEL. It is available to StackAlign only when the administrator has already enabled a trusted repository that provides it.
  - The Nginx authenticator may be a separate package and must be detected explicitly.
- acme.sh: https://github.com/acmesh-official/acme.sh
  - Shell-based ACME client with HTTP-01, DNS-01 and multiple CA support.
  - StackAlign will not clone its Git repository, run its installer, or use its curl-based bootstrap. It can use an administrator-provisioned executable only under the manual-client rules below.
- lego: https://github.com/go-acme/lego
  - MIT-licensed ACME client with HTTP-01, DNS-01, TLS-ALPN-01 and broad DNS-provider support.
  - StackAlign will not download its GitHub release binaries or build it from a downloaded source archive. It can use an administrator-provisioned executable only under the manual-client rules below.

Let's Encrypt client guidance: https://letsencrypt.org/docs/client-options/
EPEL Certbot package source: https://packages.fedoraproject.org/pkgs/certbot/certbot/

## Client availability contract

StackAlign does not download, clone, compile, install, or update ACME clients from GitHub, arbitrary URLs, or other network locations. It does not enable repositories or import repository signing keys.

A client is eligible for use through one of these administrator-controlled paths:

1. **DNF-managed client:** The package is already installed, or is available from a repository that is already enabled. StackAlign may propose installation through DNF only, preserving repository GPG verification and normal signature enforcement. For example, Certbot may be available when the administrator has already enabled EPEL.
2. **Manually provisioned client:** The administrator has independently placed the executable on the host and explicitly configured its absolute path. StackAlign does not fetch, replace, update, or claim provenance for it. Before use, implementation must verify that it is executable, root-owned, and not writable by untrusted users; record its resolved path and version in diagnostics. A manually provisioned executable is outside StackAlign's DNF package provenance guarantee.

If neither path is satisfied, stop with the stable diagnostic `error=acme_client_not_available` and identify the requested client and the missing availability path. Do not silently choose another client. The message may explain that the administrator can make the client available through an already-enabled DNF repository or provision it independently.

For DNF-managed clients, inspect installed packages and candidates from enabled repositories before planning installation. Record package name, NEVRA, repository ID and available signer/key evidence. Do not weaken GPG checks or use `--nogpgcheck`. Do not imply that a package is available merely because its upstream project exists.

## Repository policy

1. Inspect enabled repositories and package candidates with DNF before proposing installation.
2. Install only from repositories already enabled by the administrator, with `gpgcheck=1` and normal DNF signature enforcement.
3. Never add EPEL, Remi, COPR, third-party repositories, or repository signing keys automatically.
4. Never use `curl | sh`, `wget | sh`, `git clone` as an installation mechanism, unpinned "latest" downloads, or unverified release binaries.
5. Record package name, NEVRA, repository ID, and signer/key evidence in the plan and audit log when available.
6. If a client is unavailable through the configured path, report it as unavailable; do not substitute a different client silently.

## Runtime architecture

- StackAlign owns the configuration schema, plan/apply confirmation, certificate inventory, deploy/rollback orchestration, Nginx validation, service reload decision, renewal scheduling and audit output.
- The selected ACME client owns ACME protocol details and its own account/authorization state.
- One certificate lineage has exactly one configured client owner. Never run renewals through all installed clients.
- Never migrate or overwrite another client's existing certificate state automatically.
- Initial challenge mode is explicit: HTTP-01 webroot by default; DNS-01 only when a supported provider and secret source are configured. Wildcards require DNS-01.
- Secrets are root-owned, mode 0600, outside the repository and excluded from logs, snapshots and diagnostics.
- Deploy only after chain/key validation and a successful Nginx configuration test. Preserve the prior live certificate and restore it if activation fails. Reload only after a successful deployment.
- Renewal uses exactly one StackAlign scheduler backend per host: systemd timer preferred on EL 9/10; cron is an explicit fallback. Do not enable both. StackAlign must not create a second renewal schedule if the selected client already has an active scheduler; scheduling ownership must be explicit and audited.

### Coexistence and ownership contract

StackAlign owns the renewal schedule, the certificate deployment path, and the Nginx reload. ACME clients own issuance and renewal protocol operations only when invoked by StackAlign. For each certificate lineage, exactly one client is selected; other installed clients are informational and must not be invoked by StackAlign for that lineage.

#### Conflict vectors addressed

1. **Scheduler collision.** A DNF-installed Certbot may provide a systemd timer; an acme.sh installation may create a user crontab entry. Actual EL package defaults and acme.sh cron behavior must be verified on supported hosts before implementation. StackAlign preflight reports upstream scheduler state and refuses to enable its own timer while a relevant upstream scheduler is active, unless the operator explicitly passes `--allow-coexisting-schedulers`. That override records explicit acceptance of duplicate-renewal and CA rate-limit risk; it does not coordinate external jobs, prevent overlap, or make concurrent renewal safe. StackAlign never silently disables an upstream scheduler. Preferred remediation is operator-controlled disablement, for example `systemctl disable --now certbot.timer` or `acme.sh --uninstall-cronjob` executed in the owning user's context. If StackAlign cannot determine whether an external scheduler targets the same lineage, it must report the uncertainty rather than assume safety.
2. **Port 80 contention.** StackAlign never invokes standalone HTTP-01 mode or permits an ACME client to bind port 80. HTTP-01 uses webroot with the existing web server; DNS-01 is used when explicitly configured. Client-specific arguments must be verified against the pinned client version before implementation. Illustrative modes are Certbot `--webroot`, acme.sh `-w`, and Lego's HTTP webroot mode; these are not yet validated runtime command lines.
3. **Nginx config mutation.** StackAlign never invokes Certbot's `--nginx` authenticator/installer plugin. Nginx configuration is rendered only by StackAlign's template system. Certbot is restricted to webroot or an explicitly configured DNS plugin; other clients must likewise use non-mutating challenge methods.
4. **Certificate storage.** Each client retains its own account and issuance state. After successful issuance/renewal, StackAlign validates the certificate/key pair and stages the selected lineage into a same-filesystem temporary directory before atomic activation at `/etc/stackalign/certs/<domain>/fullchain.pem` and `privkey.pem`. Nginx references only the StackAlign-owned paths. Preserve the prior live pair for rollback; do not assume a history snapshot alone makes a two-file deployment atomic.
5. **Renewal lock.** Every StackAlign renewal entry point acquires an exclusive `flock` on `/var/lock/stackalign-tls.lock` before checking or changing certificate state. A second StackAlign invocation waits, then rechecks the renewal window and exits if renewal is no longer needed. This lock coordinates StackAlign processes only; it does not serialize independent Certbot/acme.sh/Lego jobs.
6. **Single reload.** StackAlign omits client deploy hooks and does not pass a command that reloads Nginx. After all selected StackAlign-managed renewals for the run have completed and any changed certificates have been validated and activated, StackAlign performs at most one safe Nginx reload. If no live certificate changed, no reload occurs. A failed validation or deployment prevents reload and triggers rollback where applicable.

#### Preflight and status interface

`stackalign tls install` performs a read-only preflight before proposing client installation or scheduler activation. It reports, without changing host state:

- Installed clients discoverable on PATH and any explicitly configured absolute executable paths. PATH lookup alone is not sufficient to authorize use; the configured path and ownership/permission checks remain authoritative.
- `certbot.timer` enabled/active state, when systemd is available.
- Certbot cron entries in locations such as `/etc/cron.d` and relevant system crontabs, where readable.
- acme.sh cron entries in the relevant user's crontab(s), including root when applicable.
- StackAlign's own timer/cron state and the configured client owner for each lineage.

If more than one relevant scheduler is active, it emits a stable warning such as `warning=tls_scheduler_overlap:active=certbot.timer,acme.sh-cron`. If a client is installed but not selected for a lineage, it emits an informational diagnostic such as `info=tls_client_present_unused:certbot`. Preflight never disables or edits an upstream scheduler and must distinguish `inactive`, `not-found`, and `unknown/unreadable` states.

The interface includes `stackalign tls status`, which reports the selected client and CA, configured domains, StackAlign deployment paths, renewal window, StackAlign scheduler state/next run, and installed-but-unused clients with their discovered paths and upstream scheduler state. Example output (illustrative, not observed host state):

```text
Active client: lego
Active CA: letsencrypt
Domains: example.com, www.example.com
Cert paths: /etc/stackalign/certs/example.com/fullchain.pem
Renewal window: 30 days
Scheduler: stackalign-tls-renew.timer (next: 2026-11-13T00:17Z)

Installed clients (informational):
  lego:       /usr/local/bin/lego
  certbot:    /usr/bin/certbot       [timer: DISABLED]
  acme.sh:    NOT PRESENT
```

#### AlmaLinux/Rocky host verification still required

The following observations are acceptance evidence, not assumptions. Run them on disposable AlmaLinux 9 and Rocky Linux 9 hosts, recording repository state and package NEVRA. Do not enable EPEL as part of the test unless that test case explicitly calls for it.

```bash
# Install behavior and timer state (test EPEL-disabled and EPEL-enabled separately).
dnf install -y certbot
systemctl is-enabled certbot.timer
systemctl is-active certbot.timer

# Cron locations and package file layout.
ls /etc/cron.d/ | grep -i certbot
rpm -ql certbot | grep -E 'letsencrypt|pki/tls'

# Run in the same account/context used to provision acme.sh.
crontab -l | grep -i acme.sh
```

Also inspect relevant system crontabs and the actual acme.sh installation mode/user. These checks determine which scheduler locations preflight must inspect. No result is claimed until captured from a real supported EL host.

## Licensing and provenance

StackAlign remains independently authored MIT code. ACME clients are separate programs installed from administrator-enabled package repositories or independently provisioned by the administrator; they retain their own licenses and notices. No client source is copied into StackAlign. A manually provisioned executable's origin and license evidence are the administrator's responsibility and must not be represented as DNF-verified. This architecture is not a legal opinion; packaging, bundling, or future linking requires a separate license review.

## Acceptance gates before implementation is marked complete

- Package availability and repository origin verified on disposable AlmaLinux 9/10 and Rocky Linux 9/10 hosts, with EPEL enabled and disabled cases clearly distinguished.
- Exact client versions and signer evidence recorded for DNF packages; manually provisioned executables tested against ownership, path and permission checks.
- EL host observations recorded for Certbot timer defaults, cron integration, package file layout, and acme.sh's actual crontab behavior/user context.
- Client command-line options verified against pinned versions; tests cover unavailable packages, disabled repositories, bad signatures, client ownership, renewal idempotency, secret permissions, failed certificate validation, failed Nginx test, rollback, lock contention, and scheduler exclusivity.
- ShellCheck, Bash syntax checks and the full existing test suite pass.
- No live certificate issuance or production deployment is claimed from mocked tests.
