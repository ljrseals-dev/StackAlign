# TLS client integration — acme.sh primary design

SPDX-License-Identifier: MIT
Author: Lewis James Seals Jr.

## Status

Design proposal only. No TLS runtime behavior is implemented by this document. No client is installed, no repository is enabled, and no certificate is issued by this change.

## Requirement

StackAlign targets AlmaLinux and Rocky Linux 9/10. StackAlign uses the Centmin Mod integration pattern: a first-party StackAlign wrapper prompts the administrator to install the upstream `acme.sh` client from its official Git repository, then integrates that client with StackAlign's Nginx and certificate deployment lifecycle.

The default ACME client is **acme.sh**. Certbot and Lego are not automatic alternatives and are not selected for new StackAlign lineages. StackAlign does not implement the ACME protocol and must not copy, vendor, fork, or translate acme.sh source.

Reference implementation: Centmin Mod's `addons/acmetool.sh` wraps acme.sh; its `acmeinstall` operation installs the upstream client and the acme.sh installer creates its daily renewal cron job. StackAlign borrows that explicit wrapper-and-client pattern, not Centmin Mod's unrelated LEMP implementation. See https://centminmod.com/letsencrypt-freessl and https://github.com/centminmod/centminmod.

Upstream client: https://github.com/acmesh-official/acme.sh

## Interactive installation contract

When StackAlign needs TLS and acme.sh is not installed, `stackalign tls install` performs a read-only preflight and then asks for explicit confirmation. It must not install anything merely because the user entered the TLS command.

Prompt (illustrative):

```text
StackAlign uses the upstream acme.sh ACME client.
Source: https://github.com/acmesh-official/acme.sh
Install location: /root/.acme.sh
The upstream installer creates a daily renewal cron entry for this account.
StackAlign will configure the certificate deployment integration after installation.
Install acme.sh now? [y/N]
```

- Default is **No**. EOF, an empty response, or any response other than an affirmative answer cancels without changing host state.
- Only after an affirmative response may StackAlign clone the official repository and run its documented local installer. Do not use `curl | sh`, `wget | sh`, or execute a remote script directly.
- The repository source, selected tag/commit, resolved commit SHA, and verification evidence must be recorded. The implementation must pin a reviewed upstream release/commit; never clone a moving branch as the production install target. Verify signed release/tag evidence against a separately pinned maintainer key where the selected upstream release supports it. If verification cannot be established, stop and report the reason.
- Do not install Git or other prerequisites silently. Report missing prerequisites and ask before proposing their installation through already-enabled DNF repositories.
- Install as the intended certificate-owning account (root for the initial StackAlign design); verify the resulting executable path, owner, permissions, and reported version before use.
- Do not overwrite or update an existing acme.sh installation without a separate explicit update confirmation. Preserve its account and certificate state.
- After installation, inspect the generated cron entry and show the exact schedule/account to the operator. The administrator confirms activation of renewal integration separately.
- If the operator declines, stop with `error=acme_client_install_declined`. Do not silently substitute Certbot, Lego, or a manually discovered executable.

The upstream acme.sh Git installation procedure is documented in its README: clone the repository and run `./acme.sh --install`. The installer creates the user's `~/.acme.sh/` home, copies the client there, and creates a daily cron job. StackAlign must account for those side effects rather than treating installation as a passive binary copy. See https://github.com/acmesh-official/acme.sh.

## Client and repository policy

1. acme.sh from `acmesh-official/acme.sh` is the primary and initially supported ACME client.
2. Installation is an explicit, interactive opt-in. No unattended install unless a future separately specified non-interactive flag requires explicit affirmative authorization and prints an equivalent plan.
3. Clone only the official upstream repository at a reviewed, pinned release/commit. Verify the source before executing its installer.
4. Do not add DNF repositories, import repository keys, or fetch unpinned release binaries.
5. Do not use remote shell pipelines such as `curl | sh` or `wget | sh`.
6. Record source URL, tag/commit, resolved commit SHA, verification result, install account, executable path, and client version in the audit output.
7. Do not automatically update acme.sh. Updates require a separate plan, source verification, and explicit confirmation.
8. Certbot or Lego already present on the host are reported as informational only. StackAlign does not invoke them, migrate their state, or claim they are coordinated with the selected acme.sh lineage.

## Runtime architecture

- StackAlign owns the command interface, configuration schema, plan/apply confirmation, domain inventory, certificate deployment/rollback, Nginx validation, and audit output.
- acme.sh owns ACME protocol operations, CA account/authorization state, and its installed renewal cron job, matching the Centmin Mod operating pattern.
- Exactly one acme.sh installation/account context owns each StackAlign-managed lineage. Never run more than one ACME client for the same lineage.
- The acme.sh cron job runs in the account in which acme.sh was installed. StackAlign must inspect and report that account and actual cron entry; it must not assume root or a particular cron implementation without checking.
- StackAlign does not create a competing systemd timer or second cron schedule for the same lineage. The upstream acme.sh cron is the renewal trigger. If it is absent, disabled, or unreadable, report the state and require explicit operator action rather than silently creating another schedule.
- Initial challenge mode is HTTP-01 webroot by default; DNS-01 only when a supported provider and root-protected secret source are configured. Wildcards require DNS-01. Do not use standalone mode that binds port 80.
- Secrets are root-owned, mode 0600, outside the repository and excluded from logs, snapshots, and diagnostics.
- acme.sh retains its own account and issuance state under its configured home. StackAlign deploys only the certificate material explicitly selected for a lineage into StackAlign-owned paths.
- Certificate deployment must validate the certificate/key pair and chain, stage files on the same filesystem, preserve the prior live pair, and support rollback if activation or Nginx validation fails.
- Nginx configuration is rendered only by StackAlign. Do not invoke acme.sh Nginx mode or allow the ACME client to mutate Nginx configuration.
- Configure an explicit StackAlign-owned deployment/reload helper for acme.sh's certificate-install/renewal callback. The helper validates and stages the renewed pair, tests Nginx configuration, activates the pair, and performs at most one safe Nginx reload after successful activation. It must not log private key material. Confirm the exact acme.sh callback flags against the pinned version before implementation.
- Use an exclusive StackAlign deployment lock (for example, `flock /var/lock/stackalign-tls.lock`) around certificate staging/activation and reload. This serializes StackAlign deployment callbacks; it does not control unrelated Certbot, Lego, or manually launched acme.sh processes.
- If no certificate changed, do not reload Nginx. A failed validation or deployment prevents reload and triggers rollback where applicable.

### Coexistence and preflight

`stackalign tls install` performs read-only checks before prompting to install acme.sh or activate integration. It reports:

- Whether the official acme.sh executable exists at the configured path, its owner, permissions, version, and configured home.
- Whether the acme.sh cron entry exists for the intended account; distinguish active, absent, unreadable, and unknown.
- Whether Certbot timers or cron entries are present, and whether other ACME clients are discoverable. These are warnings/informational only; StackAlign does not disable them.
- Whether a StackAlign deployment callback and lock configuration already exist.
- Whether the requested domains already have certificate state owned by another client.

If a different client appears to own an existing certificate lineage, stop and require an explicit migration decision. Never overwrite or adopt another client's state automatically.

Stable diagnostics include:

- `error=acme_client_install_declined`
- `error=acme_client_source_unverified`
- `error=acme_client_not_available`
- `warning=tls_external_client_present:client=certbot`
- `warning=tls_scheduler_unknown:client=acme.sh`
- `warning=tls_lineage_owned_elsewhere:domain=example.com`

`stackalign tls status` reports the selected acme.sh version/path/home, CA, domains, certificate deployment paths, renewal cron account/schedule/state, callback status, lock/deployment status, and other installed clients as informational entries. Example output (illustrative, not observed host state):

```text
ACME client: acme.sh
Version: <verified-version>
Executable: /root/.acme.sh/acme.sh
Client home: /root/.acme.sh
CA: letsencrypt
Domains: example.com, www.example.com
Renewal: acme.sh cron [active; root]
Deploy callback: StackAlign [configured]
Certificate path: /etc/stackalign/certs/example.com/
Nginx validation/reload: StackAlign helper

Other clients (not used by StackAlign):
  certbot: /usr/bin/certbot [informational]
  lego:    not found
```

## Licensing and provenance

StackAlign remains independently authored MIT-licensed code. acme.sh remains a separate upstream program under its own GPL-3.0 license and notices. StackAlign invokes the separately installed executable and does not copy, vendor, fork, or translate its source. Keep the source checkout/install process, executable, account state, and StackAlign wrapper clearly separated. Do not bundle acme.sh source into StackAlign's MIT distribution. Any future bundling, copying, linking, or derivative integration requires a separate license review; this design is not a legal opinion.

The upstream source and its license must be reviewed and recorded at the exact pinned commit used for installation. Do not imply that acme.sh is MIT-licensed or that StackAlign's MIT license replaces the client's license.

## Acceptance gates before implementation is marked complete

- Pin a reviewed acme.sh release/commit and independently verify its source/signature evidence; record the maintainer verification key fingerprint through a trusted channel.
- Test the prompted install on disposable AlmaLinux 9/10 and Rocky Linux 9/10 hosts. Confirm cancellation is side-effect-free and affirmative installation creates only the expected files and cron entry.
- Verify the exact account, cron syntax, cron execution environment, client home, and behavior after reboot on each supported EL family/version.
- Verify the exact acme.sh install-cert/deploy callback flags against the pinned version.
- Test HTTP-01 webroot and supported DNS-01 flows; verify no standalone listener and no Nginx config mutation.
- Test renewal idempotency, secret permissions, certificate/key/chain validation, failed Nginx test, rollback, lock contention, duplicate external clients, and callback failure.
- Verify CA selection explicitly; do not rely on upstream defaults that may change.
- ShellCheck, Bash syntax checks, and the full existing test suite pass.
- No live certificate issuance or production deployment is claimed from mocked tests.
