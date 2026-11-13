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
- Renewal uses exactly one scheduler backend per host: systemd timer preferred on EL 9/10; cron is an explicit fallback. Do not enable both. StackAlign must not create a second renewal schedule if the selected client already has an active scheduler; scheduling ownership must be explicit and audited.

## Licensing and provenance

StackAlign remains independently authored MIT code. ACME clients are separate programs installed from administrator-enabled package repositories or independently provisioned by the administrator; they retain their own licenses and notices. No client source is copied into StackAlign. A manually provisioned executable's origin and license evidence are the administrator's responsibility and must not be represented as DNF-verified. This architecture is not a legal opinion; packaging, bundling, or future linking requires a separate license review.

## Acceptance gates before implementation is marked complete

- Package availability and repository origin verified on disposable AlmaLinux 9/10 and Rocky Linux 9/10 hosts, with EPEL enabled and disabled cases clearly distinguished.
- Exact client versions and signer evidence recorded for DNF packages; manually provisioned executables tested against ownership, path and permission checks.
- Tests cover unavailable packages, disabled repositories, bad signatures, client ownership, renewal idempotency, secret permissions, failed certificate validation, failed Nginx test, rollback, and scheduler exclusivity.
- ShellCheck, Bash syntax checks and the full existing test suite pass.
- No live certificate issuance or production deployment is claimed from mocked tests.
