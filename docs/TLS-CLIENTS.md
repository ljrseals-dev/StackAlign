# TLS client integration — three-client lineage ownership design

SPDX-License-Identifier: MIT
Author: Lewis James Seals Jr.

## Status

Design proposal only. No TLS runtime behavior is implemented by this document. No ACME client is installed, no repository is enabled, no certificate is issued, and no production host is changed by this documentation update.

StackAlign targets AlmaLinux and Rocky Linux 9/10. This design integrates three separately installed ACME clients. They are not interchangeable global defaults: selection and ownership are explicit for each certificate lineage.

## Three-client architecture

| Client | Primary role | Typical use |
|---|---|---|
| Certbot | Standard webroot issuance and renewal | HTTP-01 for single-domain and small multi-domain sites |
| acme.sh | DNS-01 automation and provider integrations | Wildcards and DNS-01 with a supported acme.sh DNS provider |
| Lego | Additional DNS-01 / workflow fallback | A provider or workflow supported by Lego when it is not suitable with the other clients |

All three are supported integrations. StackAlign must never silently substitute one client for another, automatically fail over between them, or infer ownership from whichever executable happens to be installed.

Licensing and provenance boundaries:
- Certbot: Apache-2.0.
- acme.sh: GPL-3.0.
- Lego: MIT.
- StackAlign orchestration remains independently authored MIT-licensed code. Each client is a separately installed external executable; StackAlign does not copy, vendor, fork, translate, or link client source into its MIT-licensed tree. Separate-process invocation does not by itself settle every possible distribution or legal question; any bundling or derivative integration requires a separate license review.

Upstream project references:
- Certbot: https://github.com/certbot/certbot
- acme.sh: https://github.com/acmesh-official/acme.sh
- Lego: https://github.com/go-acme/lego

The exact supported installation source, pinned version/revision, verification method, and installation procedure for each client remain implementation acceptance gates. In particular, do not describe a downstream DNF package as an upstream repository, or assume that an official EL9/10 Certbot RPM repository exists without verification.

## Per-lineage ownership

A lineage is one certificate identity and its domain set, for example `example.com` plus `www.example.com`. Every StackAlign-managed lineage has exactly one owning ACME client at a time.

Illustrative StackAlign-owned layout:

```text
/etc/stackalign/certs/example.com/
  .client                  # certbot | acme.sh | lego
  .issued_at               # ISO-8601 timestamp
  .expires_at              # ISO-8601 timestamp
  .renewal_window_days     # policy value
  sources/
    certbot/               # client-specific source/export material
    acme.sh/
    lego/
  releases/
    <generation>/
      fullchain.pem
      privkey.pem
  current -> releases/<generation>
```

The active Nginx paths resolve through the StackAlign-controlled `current` release. Client-internal state remains in that client's own configured storage and is not referenced by Nginx. The precise path and permissions are implementation details to validate on supported hosts.

Rules:

1. `.client` is authoritative for StackAlign orchestration. `stackalign tls renew` reads it and invokes only that client for that lineage.
2. A lineage owned by Certbot is not renewed by acme.sh or Lego; the same rule applies to lineages owned by either of the other clients.
3. Installed does not mean active. Status output distinguishes installed clients from the client currently owning each lineage.
4. StackAlign never adopts another client's certificate state or overwrites another client's internal storage automatically.
5. A client switch is a deliberate migration, not fallback. No automatic failover on rate limits, challenge errors, missing plugins, or client outages.
6. The ownership record and deployment state must be protected against partial writes, concurrent commands, and tampering. The implementation must define recovery behavior for missing, malformed, or conflicting ownership metadata.

## Renewal schedulers: global scope is a safety boundary

A per-lineage ownership file does not automatically constrain a client's native scheduler. Certbot timers, acme.sh cron jobs, and any externally configured Lego automation may operate at a broader installation/account scope and may process client-managed lineages without consulting StackAlign's `.client` file.

Therefore:

- Preflight inventories native timers, cron entries, service units, and relevant client renewal configurations for all three clients. It reports the account, executable/configuration path, and whether state is active, inactive, unreadable, or unknown.
- StackAlign must not claim that a scheduler is safely gated merely because `.client` exists.
- A native scheduler that can renew a StackAlign lineage without checking StackAlign ownership is a conflict unless isolation is demonstrated.
- The implementation must choose and test an explicit scheduler strategy: isolate StackAlign-managed client state so native renewal can only see lineages assigned to that client; or disable/gate native renewal for the isolated StackAlign client context and have StackAlign invoke the recorded owner. Do not disable a host-wide scheduler if that would disrupt unrelated administrator-managed certificates.
- `--allow-upstream-schedulers`, if ever implemented, is an explicit risk acknowledgement only. It is not a lock, gate, or proof of per-lineage scheduler isolation and must not be presented as making conflicting schedulers safe.
- StackAlign's deployment lock serializes StackAlign staging and activation. It cannot prevent an unrelated client process from issuing or renewing a certificate concurrently.
- If scheduler ownership or isolation cannot be established, preflight stops before enabling renewal integration and explains the conflict. No automatic scheduler disablement or silent schedule creation is permitted.

The exact Certbot timer behavior and storage layout for the selected AlmaLinux/Rocky installation source, the account and cron behavior of the chosen acme.sh install method, and any external Lego scheduling must be verified on disposable supported hosts. Do not hardcode assumptions from Debian/Ubuntu or another distribution.

## Issuance, deployment, and renewal

StackAlign owns the command interface, configuration schema, domain inventory, lineage ownership metadata, certificate validation, deployment activation/rollback, Nginx validation/reload, and audit output. The selected ACME client owns ACME protocol operations, its CA account/authorization state, and its client-specific issuance state.

- Certbot's standard path is HTTP-01 webroot. StackAlign must not allow a client plugin to mutate Nginx configuration when StackAlign owns Nginx rendering.
- acme.sh is used for supported DNS-01 provider automation and other explicitly selected supported workflows. Wildcard certificates require DNS-01.
- Lego is an additional explicitly selected client for supported provider/workflow cases. It is not an automatic substitute.
- DNS credentials are root-protected, mode 0600, outside the repository, and excluded from logs, snapshots, and diagnostics.
- Client output is staged into a StackAlign-controlled location. Before activation, validate the certificate, private-key match, chain, subject/SAN set, validity interval, and expected lineage identity.
- Nginx references only StackAlign-controlled deployed paths, never client-internal storage.
- Deployment must preserve the previous working release and activate a complete certificate/key pair as one recoverable generation. The implementation must use a same-filesystem atomic activation mechanism (for example, an atomic pointer switch to a versioned release directory), rather than assuming two independent file renames are jointly atomic.
- Test Nginx configuration before reload. Reload at most once after successful activation. If validation or activation fails, restore the previous active generation and verify the service remains on the previous valid certificate. Do not reload after a failed validation.
- Use an exclusive StackAlign lock around lineage operations and deployment. Define lock scope and stale-lock recovery before implementation.
- No private key material may appear in command output, logs, diagnostics, or audit records.

## Explicit migration between clients

Example:

```bash
stackalign tls migrate example.com --to acme.sh --challenge dns-01 --dns-provider cloudflare
```

Migration is operator-initiated and must not modify the active lineage until the target client has issued and StackAlign has validated a replacement certificate.

Required transaction outline:

1. Read and validate the current owner and lineage identity.
2. Confirm target client availability, installation provenance, required challenge support, credential source, and scheduler isolation.
3. Issue into the target client's isolated source/state area. Do not overwrite the current deployed release.
4. Validate the new certificate, key match, chain, SANs, and validity.
5. Take a recoverable snapshot or retain the previous immutable release.
6. Stage a complete new release and atomically activate it.
7. Update the ownership record with a recoverable transaction protocol so metadata and active certificate cannot be left disagreeing after a crash.
8. Test Nginx configuration and perform one safe reload.
9. On any failure, restore the previous active release and ownership record, then verify the previous service state. Exit non-zero and report the recovery result.

The implementation must define crash recovery for failures between activation, ownership metadata update, Nginx test, and reload. Two independent `mv` operations for certificate and key are not a sufficient atomic-pair guarantee. Migration does not automatically delete the former client's account or source state; cleanup is a separate explicit operation after successful migration and review.

## Status and observability

`stackalign tls status` reports each lineage's domain set, owner, CA, challenge type/provider where known, expiry, renewal window, deployed path, and renewal/scheduler state. It separately lists installed but currently unused clients.

Illustrative output only; not observed host state:

```text
Domain: example.com, www.example.com
  Client: certbot
  CA: letsencrypt
  Challenge: http-01 (webroot)
  Expires: <certificate-expiry>
  Renewal window: 30 days
  Deployed: /etc/stackalign/certs/example.com/current/fullchain.pem

Domain: wildcard.example.org
  Client: acme.sh
  CA: <configured-ca>
  Challenge: dns-01 (cloudflare)
  Expires: <certificate-expiry>
  Renewal window: 30 days

Installed clients not currently owning a StackAlign lineage:
  lego: <verified-executable-path>
```

Status must distinguish facts observed on the host from unknown or unreadable state. It must not fabricate a CA, expiry, scheduler status, provider, or executable path.

Stable diagnostics should identify client and lineage without exposing secrets, for example:

- `error=tls_client_install_declined`
- `error=tls_client_source_unverified:client=<client>`
- `error=tls_client_not_available:client=<client>`
- `error=tls_scheduler_conflict:client=<client>`
- `error=tls_scheduler_state_unknown:client=<client>`
- `error=tls_lineage_owner_missing:domain=<domain>`
- `error=tls_lineage_owned_elsewhere:domain=<domain>`
- `error=tls_migration_rollback_failed:domain=<domain>`

## Installation and operator consent

Each client installation is a separate explicit opt-in. A StackAlign TLS command must not silently install a client, enable a repository, import a key, disable a scheduler, or install prerequisites.

Before prompting, perform a read-only preflight and show the selected client, upstream/source, pinned version or revision, install account and path, expected side effects, scheduler implications, and required dependencies. Default to No. EOF, empty input, or any non-affirmative response cancels without host changes.

Do not use remote shell pipelines such as `curl | sh` or `wget | sh`. Do not update an existing client installation without separate confirmation. Record source, pinned revision/version, verification evidence, install account, executable path, and client version. If source verification cannot be established, stop.

The precise installation mechanism for each client is intentionally unresolved until upstream guidance and EL9/10 host behavior have been verified. Do not assume a particular DNF repository, Snap availability, cron behavior, timer name, or filesystem layout.

## Acceptance gates before implementation

- Review and pin the upstream source/version for Certbot, acme.sh, and Lego; verify source integrity and record provenance independently.
- Verify license notices and keep all three clients separate from the StackAlign MIT source tree.
- Test prompted installation, cancellation, prerequisites, permissions, and existing-install preservation on disposable AlmaLinux 9/10 and Rocky Linux 9/10 hosts.
- Determine Certbot storage paths and renewal scheduler behavior for the selected EL installation method.
- Determine acme.sh account, home, cron syntax, execution environment, and renewal callback behavior for the selected install method.
- Determine whether and how Lego renewal is scheduled in the supported integration; do not assume it has an upstream scheduler.
- Prove scheduler isolation: a client scheduler must not renew a StackAlign lineage assigned to another client, and StackAlign must not disrupt unrelated administrator-managed certificates.
- Test HTTP-01 webroot and supported DNS-01 providers, wildcard issuance, secret permissions, and no Nginx configuration mutation by clients.
- Test lineage ownership enforcement, concurrent invocation, lock contention, client failure, rate limits, migration, crash recovery, certificate/key/chain validation, atomic activation, Nginx test failure, rollback, and callback failure.
- Verify no silent client substitution, automatic failover, or cross-client state adoption.
- Run Bash syntax checks, ShellCheck where available, and the full existing test suite. No test result is claimed by this documentation update.
- No live certificate issuance or production deployment is claimed from mocked tests.

## Scope boundary

This PR is documentation/design only. It does not add `lib/tls.sh`, `lib/tls_migrate.sh`, client installers, scheduler changes, renewal hooks, or executable TLS behavior. Those implementation files remain blocked on design review and host-based acceptance evidence.
