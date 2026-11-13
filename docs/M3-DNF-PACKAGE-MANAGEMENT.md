# M3 — DNF Package Management and Mirrors

<!-- SPDX-License-Identifier: MIT -->
<!-- Author: Lewis James Seals Jr. -->

Status: DESIGN / NOT IMPLEMENTED  
Target: AlmaLinux 9/10 and Rocky Linux 9/10, x86_64  
Primary package path: DNF/RPM  
Source-build exception: deferred; requires a measured compatibility or performance case and separate approval.

## 1. Scope and non-claims

M3 adds a safe package-management layer around the platform package manager. DNF remains responsible for repository selection, metalink/mirrorlist failover, metadata handling, dependency solving, RPM transactions, and package signature enforcement.

M3 does not compile upstream source tarballs, implement a second repository resolver, or claim that an RPM transaction is a complete machine snapshot. No package version, digest, key fingerprint, mirror priority, or tested-OS claim is valid until independently verified and recorded with its source.

The current `vendor/versions.toml` contains source-tarball coordinates and explicit placeholder digests/fingerprints. Those fields are not suitable as an RPM package manifest and must not be silently reinterpreted. A separately reviewed schema migration is required before the manifest becomes install input.

## 2. Security invariants

1. Never pipe network data directly to an extractor or package manager.
2. Use HTTPS for StackAlign-managed artifact downloads; reject redirects to non-HTTPS protocols.
3. Write downloads to a private temporary file in the destination filesystem, validate the completed file, then rename it into place.
4. Never treat SHA-256 alone as publisher authentication. RPM authenticity is established by RPM signature verification against an explicitly trusted signing key; repository metadata verification is enabled where the repository publishes signed metadata.
5. Do not import a key merely because it was downloaded from a configured URL. Validate its primary-key fingerprint against an independently pinned fingerprint before import. Require an unambiguous primary-key record.
6. DNF-managed repositories use native `metalink` or `mirrorlist` configuration where supplied by the vendor. StackAlign must not replace DNF's repository failover with a hand-rolled URL loop.
7. Never disable `gpgcheck` to make installation succeed. A repository requiring signed metadata must use `repo_gpgcheck=1`; if upstream does not sign metadata, document that limitation explicitly rather than pretending it is verified.
8. Treat repository configuration, signing keys, package cache, transaction history, and service configuration as separate trust/state domains.
9. Package names, NEVRA strings, repository IDs, and manifest values are data. Validate them against strict syntax/allowlists; never `eval` or source TOML as shell.
10. Do not delete the last known-good cached RPM until a later transaction and health check have completed and the retention policy permits deletion.

## 3. Mirror architecture

### 3.1 DNF repositories

For AlmaLinux, Rocky Linux, EPEL, Remi, and MariaDB, prefer the vendor-supported repository configuration and its documented metalink/mirrorlist/CDN endpoint. DNF performs mirror selection and retry behavior for repository metadata and package downloads.

`vendor/mirrors.toml` is an inventory/policy document, not a replacement for native DNF configuration. Each entry must distinguish:
- repository ID and owning vendor;
- supported OS major versions and architectures;
- canonical repository configuration source;
- whether metadata signatures are published and verified;
- package-signing key fingerprint(s), with primary-key semantics;
- upstream mirrorlist/metalink URL or canonical CDN endpoint;
- any documented fallback endpoint and the evidence supporting it;
- date checked and source references.

Do not label a host “tier-0”, “guaranteed”, or “100 Gbit/s” without a current authoritative source and a clearly defined meaning. Avoid hard-coding individual mirror nodes when the vendor provides a maintained mirror manager.

### 3.2 StackAlign-managed downloads

`lib/fetch.sh` is only for StackAlign-owned release assets, pinned key files, and other explicitly declared standalone artifacts that are not already managed by DNF. It must not fetch arbitrary RPMs around DNF's dependency solver.

Proposed interface:
- `sa_fetch_url <url> <output_file> [fallback_url ...]`: download to a same-filesystem temporary path, enforce HTTPS, bounded connect/overall timeouts, failover only after a failed attempt, and atomically publish the completed file. A failed attempt must never leave a partial output that a caller can mistake for success.
- `sa_fetch_verify <file> <expected_sha256>`: validate a strictly formatted 64-hex expected digest and compare it to the file digest. This is transport/integrity checking, not publisher authentication.
- Callers must separately perform publisher signature/fingerprint verification where required.

The helper must not log secrets embedded in URLs. It must not follow a redirect to a non-HTTPS protocol. Temporary files must be private and cleaned on every exit path.

## 4. RPM cache policy

The preferred cache is DNF's own package cache with retention configured deliberately. A StackAlign-managed `vendor/cache/` is optional and must not be introduced until the implementation can key entries by complete NEVRA plus architecture and verify every cached RPM with `rpm --checksig` (or equivalent `rpm -K`) before use.

If a StackAlign-managed cache is implemented:
- use a private, administrator-owned directory outside the source checkout by default; `vendor/cache/` is a development/test fixture location only and must be git-ignored;
- never trust cache presence as proof of integrity or authenticity;
- verify the RPM signature on every cache read, not only at initial download;
- install through DNF using the verified local RPM path so dependency resolution remains active;
- retain the exact prior NEVRA package artifacts needed for downgrade;
- use atomic temporary-file publication and reject symlinks or non-regular cache entries;
- define ownership, permissions, disk limits, pruning, and cache-corruption behavior.

## 5. Upgrade and downgrade transaction contract

A future `stackalign update <component> <version>` implementation must be plan-first and require explicit `--apply` for mutation.

Before mutation:
1. Resolve the requested component/version to an exact package set and NEVRA.
2. Check the supported OS major version, architecture, repository enablement, and tested-version policy.
3. Show the complete DNF transaction plan, including installs, upgrades, downgrades, removals, and dependency changes.
4. Refuse untested versions unless the user explicitly supplies `--force`; `--force` does not bypass signature checks or compatibility hard refusals.
5. Snapshot the relevant configuration and record installed package NEVRAs and enabled repository state.
6. Ensure the previous package versions required for recovery remain obtainable (cached exact RPMs or an explicitly verified repository source).

During mutation:
1. Run DNF with noninteractive confirmation only after StackAlign's own explicit apply/confirmation gate.
2. Preserve DNF transaction output and transaction ID for audit.
3. Never claim RPM transaction atomicity implies atomic service availability or configuration rollback.

After mutation:
1. Verify installed NEVRAs and RPM signatures.
2. Run component-specific configuration validation and service health checks.
3. On failure, restore configuration snapshots and perform an explicit DNF downgrade/reinstall to the recorded previous NEVRAs using verified artifacts.
4. Restart/reload affected services and recheck health.
5. If recovery fails, stop and report a critical manual-recovery state; do not continue with additional package operations.

Rollback is a coordinated recovery procedure, not a single atomic filesystem rename. It cannot guarantee restoration of mutable application data, database contents, or external service state. Database upgrades require their own backup/restore and compatibility contract and are outside the first M3 package transaction.

## 6. CLI and module boundaries

- `lib/fetch.sh`: standalone artifact download and digest helper only.
- `lib/repo.sh`: repository configuration, key trust, package install/upgrade/downgrade operations; DNF remains the transaction engine.
- `lib/history.sh`: configuration snapshots and recovery metadata; not a substitute for preserving package artifacts or DNF transaction IDs.
- `lib/service.sh`: health checks and controlled service recovery; callers must snapshot before changing configuration.
- `bin/stackalign`: plan/apply UX and argument validation. The existing CLI currently marks `update` as an M5 stub; changing its milestone/behavior requires a separately reviewed scope decision.
- `vendor/versions.toml`: future package-coordinate schema, not yet authoritative.
- `vendor/mirrors.toml`: reviewed vendor repository/mirror inventory, not a hand-maintained mirror speed ranking.

## 7. Test requirements

The fetch helper test suite must use fake `curl`, `sha256sum`, and controlled fixtures. It must cover:
- primary succeeds and publishes exact bytes;
- primary fails and first valid fallback succeeds;
- all sources fail and no output is published;
- interrupted/partial download is not published;
- digest match succeeds;
- digest mismatch fails and removes/quarantines the temporary artifact;
- malformed digest and non-HTTPS URL are rejected;
- redirect/protocol restrictions are enforced by the curl invocation;
- output path symlink and unsafe parent cases fail closed;
- no real network call occurs in unit tests.

Repository/package tests must use fake `dnf`, `rpm`, and `gpg`; no test may modify the host package database or import a real key. Cover signature failure, wrong key, missing previous NEVRA artifact, dependency/removal preview, DNF failure, health-check failure, successful recovery, and failed recovery.

CI tests establish shell-level behavior only. Live repository behavior, RPM signing-key rotation, DNF transaction behavior, and service recovery require disposable AlmaLinux/Rocky VMs.

## 8. Dependencies and execution gates

- Gate 0: PR #8 security changes must be reviewed against its actual diff and required CI must pass. Merge remains a human-authorized action.
- Gate 1: freeze this M3 contract and confirm its boundaries against the current repository.
- Gate 2: implement and test `lib/fetch.sh` as a standalone helper.
- Gate 3: document vendor repository metadata and signing-key sources; do not fill placeholder fingerprints or package versions by guesswork.
- Gate 4: design and test RPM cache policy before changing `lib/repo.sh`.
- Gate 5: implement plan/apply package transactions and recovery only after package manifest and cache contracts are approved.
- Gate 6: validate on disposable AlmaLinux and Rocky Linux hosts. Do not claim EL 10 support until tested.

M2b physical memory measurement remains a separate paused gate. M3 work must not change `lib/tune.sh`, T1–T28, or the `SA_PHP_CHILD_MIB=30` assumption.

## 9. Current implementation status

This document is a proposal. It does not claim that `lib/fetch.sh`, mirror inventory, package cache, update/downgrade commands, RPM verification workflow, or live-host tests exist. No package versions, checksums, fingerprints, or test results are asserted here.
