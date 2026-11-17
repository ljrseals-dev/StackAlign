# StackAlign beta scope and hosting clarification

**Purpose:** Correct the interpretation of StackAlign's existing LEMP beta and distinguish ordinary web hosting from independent-user shared hosting.

## Project scope

StackAlign is a Bash CLI for installing and administering an EL-family LEMP web-hosting stack. Its scope includes web hosting and virtual-host (vhost) workflows. The fact that StackAlign is not a browser-based commercial hosting control panel does not mean it cannot host websites or manage web-server virtual hosts.

The beta's existing LEMP bootstrap installs distribution-provided Nginx, MariaDB, PHP-FPM, and PHP MySQL support on supported EL9 x86_64 systems. The current bootstrap's default HTTP endpoint is loopback-only. Public ingress, DNS, TLS automation, and firewall changes are separate capabilities and must be described according to their actual implementation status.

## PHP-FPM pool behavior

The default PHP-FPM configuration uses the shared `www` pool. Additional pool configurations are an operator-selectable CLI choice; they are not enabled automatically by default. Documentation must not imply that every site or account automatically receives a dedicated pool, nor that the shared default pool is per-account isolation.

When documenting or changing pool selection, preserve these distinctions:

- The default install path uses the shared `www` pool.
- An operator may choose additional PHP-FPM pools through the CLI where that configuration workflow is available.
- A dedicated pool can provide a separate PHP-FPM execution context, but its actual Unix identity, socket permissions, filesystem access, process limits, and service boundaries must be checked before claiming independent-user isolation.
- Vhost routing and PHP-FPM pool selection are related configuration concerns, but they are not interchangeable.

Do not silently change the existing default pool behavior as part of documentation cleanup.

## Hosting scope versus independent-user isolation

These are distinct deployment models:

1. **Administrator-managed web hosting:** One administrator operates a server, manages multiple websites/vhosts, and chooses the PHP-FPM pool arrangement appropriate to those sites. This is within StackAlign's web-hosting scope.
2. **Independent-user shared hosting:** Multiple mutually untrusted end users receive separate accounts and must be isolated from one another. This requires additional verified controls for Unix identities, PHP-FPM pool/socket ownership, filesystem permissions, process/resource boundaries, and related service access.

A limitation on the second model must not be written as a prohibition on the first. A shared `www` pool is the default, not proof that vhosts are unsupported. Conversely, the existence of vhosts or optional pools alone is not proof of complete multi-tenant isolation.

## Existing pull requests

Do not recreate work already present in open PRs. Review and validate the existing branches in their dependency order, and treat their test/CI state as belonging to their exact PR heads:

- PR #61: read-only site/vhost inventory.
- PR #62: fixture coverage stacked on PR #61.
- PR #60: earlier overlapping site/vhost inventory implementation; reconcile rather than duplicate.
- PR #63: database credential-boundary regression tests.
- PR #64: SFTP password exposure fix.

These PRs are implementation work already in progress. Their existence is not evidence that they have merged or passed fresh CI.

## Beta completion objective

The immediate objective is to complete and publish the existing StackAlign beta—not to redefine the project as a non-hosting toolkit or make every future independent-user hosting feature a prerequisite for the LEMP beta.

Release work should focus on:

- preserving the existing working LEMP bootstrap and user-built checkouts;
- completing the release artifact, versioning, checksum/signature verification, and installer path;
- validating the documented EL9 install behavior and recovery boundaries;
- completing existing PR work without duplicating it;
- accurately documenting vhost and PHP-FPM pool behavior;
- separating implemented beta capabilities from optional or future hosting capabilities.

## Documentation correction requirement

The current `docs/Technical Manual.md` contains obsolete statements that StackAlign does not install a functioning web stack and that Nginx/PHP-FPM configuration is only specified. Those statements conflict with the current `lib/lemp.sh` implementation and `docs/LEMP-BETA.md`. Treat the Technical Manual as a historical design document until it is reconciled with current source. Do not use its outdated introductory claims as the authoritative description of the current beta.

## Evidence language

Keep implementation, automated test coverage, CI results, and real-host validation separate. Never claim that a feature is production-ready merely because it exists, and never claim that a feature is absent merely because a separate, more demanding deployment model remains blocked.
