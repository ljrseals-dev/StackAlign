# TLS client integration — repository-first design

SPDX-License-Identifier: MIT
Author: Lewis James Seals Jr.

## Status

Design proposal only. No TLS runtime behavior is implemented by this document. No repository is enabled, no package is installed, and no certificate is issued by this change.

## Requirement

StackAlign targets AlmaLinux and Rocky Linux 9/10. TLS support must reuse maintained ACME client projects and the host's already-configured, GPG-checked DNF repositories. StackAlign must not copy, vendor, fork, or translate an ACME client's implementation.

## Upstream projects

- Certbot: https://github.com/certbot/certbot
  - Let's Encrypt recommends Certbot as the starting client for most users.
  - Use the package from an already-enabled, trusted DNF repository (commonly EPEL on EL); do not silently enable EPEL or install via an unverified bootstrap.
  - The Nginx authenticator is a separate package on RPM systems and must be detected explicitly.
- acme.sh: https://github.com/acmesh-official/acme.sh
  - Shell-based ACME client with HTTP-01, DNS-01, Nginx and Apache modes and support for multiple CAs.
  - Use an already-enabled DNF package when present. Keep its own installation home and account/certificate state separate from StackAlign.
  - Install with upstream cron disabled if StackAlign owns scheduling.
- lego: https://github.com/go-acme/lego
  - MIT-licensed ACME client with HTTP-01, DNS-01, TLS-ALPN-01 and a broad DNS-provider set.
  - Prefer an already-enabled trusted DNF repository package if one is available. Do not assume EL 9/10 has one. A pinned upstream release-binary path is a separately reviewed fallback, not an automatic repository addition.

Let's Encrypt's client guidance: https://letsencrypt.org/docs/client-options/
EPEL package source for Certbot: https://packages.fedoraproject.org/pkgs/certbot/certbot/

## Repository policy

1. Inspect enabled repositories and package candidates with DNF before proposing installation.
2. Install only from repositories already enabled by the administrator, with gpgcheck=1 and normal DNF signature enforcement.
3. Never add EPEL, Remi, COPR, third-party repos, or repository signing keys automatically.
4. Never use curl-to-shell bootstrap, --nogpgcheck, or unpinned "latest" downloads.
5. Record package name, NEVRA, repository ID, and signer/key evidence in the plan and audit log.
6. If a client is unavailable from enabled repositories, report it as unavailable; do not substitute a different client silently.

## Runtime architecture

- StackAlign owns the configuration schema, plan/apply confirmation, certificate inventory, deploy/rollback orchestration, Nginx validation, service reload decision, renewal scheduling and audit output.
- The selected ACME client owns ACME protocol details and its own account/authorization state.
- One certificate lineage has exactly one configured client owner. Never run renewals through all installed clients.
- Never migrate or overwrite another client's existing certificate state automatically.
- Initial challenge mode is explicit: HTTP-01 webroot by default; DNS-01 only when a supported provider and secret source are configured. Wildcards require DNS-01.
- Secrets are root-owned, mode 0600, outside the repository and excluded from logs, snapshots and diagnostics.
- Deploy only after chain/key validation and a successful Nginx configuration test. Preserve the prior live certificate and restore it if activation fails. Reload only after a successful deployment.
- Renewal uses exactly one scheduler backend per host: systemd timer preferred on EL 9/10; cron is an explicit fallback. Do not enable both.

## Licensing and provenance

StackAlign remains independently authored MIT code. ACME clients are separate programs installed from their upstream/package repositories and retain their own licenses and notices. No client source is copied into StackAlign. This architecture is not a legal opinion; packaging, bundling, or future linking requires a separate license review.

## Acceptance gates before implementation is marked complete

- Package availability and repository origin verified on disposable AlmaLinux 9/10 and Rocky Linux 9/10 hosts.
- Exact client versions and signer evidence recorded; no guessed versions or fingerprints.
- Tests cover unavailable packages, disabled repositories, bad signatures, client ownership, renewal idempotency, secret permissions, failed certificate validation, failed Nginx test, rollback, and scheduler exclusivity.
- ShellCheck, Bash syntax checks and the full existing test suite pass.
- No live certificate issuance or production deployment is claimed from mocked tests.
