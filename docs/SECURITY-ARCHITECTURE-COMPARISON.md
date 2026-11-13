# Security architecture comparison and StackAlign policy

SPDX-License-Identifier: MIT

Copyright (c) 2026 Lewis James Seals Jr.

## 1. Purpose and scope

This document records the security architecture StackAlign intends to implement and compares selected design choices with publicly documented Centmin Mod behavior. It is an engineering decision record, not a security certification, penetration-test report, or claim that either project is universally safer.

StackAlign targets EL-family x86_64 systems, with AlmaLinux and Rocky Linux 9/10 as its intended deployment platforms. Ubuntu is a CI environment, not a supported deployment target.

**Current project limitation:** StackAlign is an early-stage foundation. It does not yet install Nginx, PHP-FPM, or MariaDB, and its README explicitly says it is not production-ready. The policies below are requirements and acceptance criteria, not claims of completed runtime enforcement.

The governing rule is: **measure, do not claim.**

## 2. Executive comparison

| Concern | Centmin Mod — documented approach | StackAlign — adopted policy |
|---|---|---|
| Platform | Newer branches document AlmaLinux and Rocky Linux support, including EL8/EL9 and EL10 development work | Explicit target: AlmaLinux/Rocky Linux 9 and 10, x86_64 |
| Package strategy | Integrated stack with substantial upstream and custom build/update workflows | DNF packages are the default; source builds require a documented, measured exception |
| EOL software | Centmin Mod has published security backports for EOL PHP branches and also recommends upgrading to supported PHP where applications permit | Refuse unsupported software by default; allow a narrowly scoped, time-bounded exception only with documented maintenance evidence and operator approval |
| Package trust | Trust depends on the selected upstream, repository, build, and signing chain | Explicit repository inventory, signature verification, primary-key fingerprint pinning, and recorded provenance |
| Configuration and rollback | Centmin Mod has its own configuration and update mechanisms; this document does not claim they are absent or inadequate | StackAlign must make changes reviewable, snapshot relevant prior state, and prove recovery before claiming rollback protection |
| Security checks | Centmin Mod publishes security-related tools and update guidance | Findings must distinguish detection, diagnosis, patch availability, and successful remediation |
| Runtime status | Centmin Mod is an integrated LEMP stack | StackAlign is not yet a functioning LEMP installer; implementation and host validation remain open |

This is a comparison of operating models. It is not a ranking of overall security.

## 3. What the Centmin Mod evidence establishes

Centmin Mod's own published material documents support for AlmaLinux and Rocky Linux, and its newer development branch has been used for AlmaLinux 10 testing. It is therefore inaccurate to characterize current Centmin Mod as CentOS-only.

Centmin Mod has also published backported PHP security fixes for end-of-life PHP branches. Its October 2026 update describes backports for PHP 7.2, 7.3, 7.4, 8.0, and 8.1, and instructs operators to update Centmin Mod and rebuild PHP to receive those patches. The same update recommends upgrading to a supported PHP version where application compatibility permits.

That model can preserve compatibility for legacy applications, but it creates an ongoing maintenance obligation: patch selection, adaptation to older code, build reproducibility, release timing, and operator rebuilds must all be trusted. Backporting is not inherently insecure; its safety depends on the quality, completeness, review, and timely delivery of each backport.

StackAlign deliberately chooses a different default: avoid owning a parallel source-build and backport maintenance program when a supported distribution package can meet the requirement. If a future requirement makes a source build unavoidable, that exception must be justified and separately governed.

### Public references

- Centmin Mod, AlmaLinux/Rocky Linux support announcement: https://community.centminmod.com/threads/131-00stable-140-00beta01-release-with-almalinux-rocky-linux-support.25572/
- Centmin Mod, PHP security updates and EOL backports (October 2026): https://community.centminmod.com/threads/php-8-5-12-8-4-27-8-3-36-8-2-35-critical-security-updates-and-eol-php-7-4-8-1-backports.33134/
- Centmin Mod, PHP 8.2.35 security backports for EOL PHP 7.2/7.3: https://community.centminmod.com/threads/backport-php-8-2-35-security-fixes-to-php-7-2-7-3-eol-in-132-00stable.33146/

These are project-published statements and release notes. They are evidence of the documented approach, not an independent audit of every Centmin Mod release or installation.

## 4. StackAlign package and provenance policy

### 4.1 DNF-first

DNF is the primary package-management interface for supported EL systems. Prefer distribution-supported packages and repositories because the operating-system vendor provides package metadata, dependency integration, signing, and an established update channel.

This preference does not mean every package available through DNF is equally trusted. DNF can use distribution, EPEL, vendor, and third-party repositories. StackAlign must identify the source of each package and apply the trust policy to the repository that supplies it.

A valid package signature establishes that the package matches the signing key accepted by the host. It does not prove that the package is vulnerability-free, that the signing key has never been compromised, or that the publisher's build process is secure.

### 4.2 Repository inventory and trust

Before package installation, StackAlign must:

1. Inventory enabled repositories and their repository IDs, base URLs or mirror configuration, enabled state, and configured signing-key locations.
2. Identify which repository is expected to supply each requested package.
3. Reject an unexpected repository or an unapproved package source.
4. Require RPM package signature verification; never silently set `gpgcheck=0`.
5. Require repository metadata signature verification when the repository publishes supported metadata signatures; do not pretend this check exists when the repository does not provide them.
6. Pin and verify the expected primary-key fingerprint before trusting a newly introduced signing key.
7. Record the repository, package NEVRA, signing-key identity, and verification outcome in the transaction record.
8. Fail closed on missing, ambiguous, changed, or unverifiable trust material.

Fingerprint validation must identify the primary key correctly. Subkeys are not additional primary keys. A parser must not count every `fpr:` record as a separate primary key; it must associate the fingerprint with the relevant primary `pub:` record and verify the expected primary fingerprint.

StackAlign must not import keys merely because a repository file names a URL. Key acquisition, fingerprint review, and trust acceptance must be explicit and auditable.

### 4.3 Third-party repositories

Third-party repositories are opt-in, not silently enabled dependencies.

Before enabling one, the operator must see:

- Publisher and repository identity
- Intended packages and why the distribution package is insufficient
- Repository URL and signing-key fingerprint
- Package and metadata signature-verification behavior
- Update and support responsibility
- Disable/removal and rollback implications

A third-party repository must not silently replace an already selected package source or introduce unrelated package updates.

### 4.4 Source builds

Source compilation is not the default path. It creates additional responsibilities for source provenance, patch tracking, compiler flags, build reproducibility, dependency management, security updates, installation layout, and rollback.

A source build may be considered only when a concrete requirement cannot be met through supported packages. Any exception must specify the reason, upstream source and immutable revision, patch set, build recipe, dependencies, license notices, verification steps, update owner, and retirement plan. No generic “performance” or “newer version” rationale is sufficient without measurements and compatibility evidence.

## 5. Software lifecycle and EOL policy

StackAlign must not equate an upstream version number with the actual support state of a distribution package. Enterprise Linux vendors may backport security fixes while retaining an older upstream version string.

The lifecycle decision must therefore consider:

1. The operating-system release lifecycle.
2. The package publisher and repository.
3. The publisher's security-maintenance commitment for that package.
4. Published advisories and errata, including backported fixes.
5. Whether the installed package is within the publisher's supported lifecycle.
6. Whether the application itself still supports the selected runtime.

**Default rule:** refuse software that is unsupported by its responsible publisher, unless the operator explicitly approves a documented exception.

An exception for an upstream-EOL branch is not a claim that the branch is generally supported. It must include a named patch maintainer, evidence of the exact fixes applied, a reproducible build or trusted signed package, a defined update cadence, an expiration/review date, and a migration plan. If any of these conditions cannot be established, StackAlign must refuse the exception.

StackAlign must never label an EOL component “secure” solely because a patch is said to have been backported. It may report that a specific advisory is reported as addressed, with the source and verification status, while still reporting the branch as upstream-EOL.

## 6. Configuration history, transactions, and rollback

StackAlign's intended model is explicit state change with recoverable history, not silent mutation.

Before a mutating operation, the implementation must:

- Identify the exact files, package state, services, and repository settings it may change.
- Validate paths and refuse unsafe symlink or path traversal conditions.
- Capture only the required prior state, excluding secrets from logs and ordinary snapshots.
- Write new files through private same-filesystem temporary files and atomic replacement where applicable.
- Preserve ownership, permissions, and security labels where required.
- Record the operation, inputs, affected paths, and outcome without recording credentials or private key material.
- Verify the resulting state before declaring success.

Rollback must be a tested recovery procedure, not merely restoration of a file copy. It must verify restored content, permissions, ownership, service configuration, and service health where relevant. A rollback failure must be reported as a failure; it must not be represented as successful recovery.

The existence of history or rollback commands in the current foundation does not prove that every future package, service, or configuration transaction is recoverable. Each mutating subsystem needs its own failure-injection and recovery tests.

## 7. Security checks: detection is not remediation

StackAlign must distinguish the following states in output and records:

- **Detected:** a scanner or check found a condition.
- **Not detected:** the check did not find the condition within its stated coverage.
- **Unknown:** the check could not run, lacked permissions, or could not establish the relevant state.
- **Advisory available:** a publisher has issued relevant security information.
- **Remediation available:** a specific fix or update is identified.
- **Remediation applied:** the change was actually performed.
- **Remediation verified:** post-change checks confirm the intended state.

A clean scanner result is not proof of security. A failed or incomplete scan is not a clean result. A package update being available is not proof that it was installed. A successful package transaction is not proof that an application is no longer vulnerable.

Security tooling should be additive: it must not substitute for vendor updates, supported software lifecycles, secure configuration, or incident response.

## 8. Threat model and scope boundaries

StackAlign's initial threat model should focus on the installer and host-management boundary:

- Unexpected or malicious package sources
- Signing-key substitution or unreviewed key import
- Repository configuration tampering
- Unsafe path handling and symlink attacks
- Partial writes and interrupted transactions
- Incorrect rollback or incomplete recovery
- Secret disclosure through logs, snapshots, process arguments, or Git history
- Privilege misuse and unintended service changes
- Stale, unsupported, or unpatched runtime components
- Misleading status output that reports assumptions as facts

The threat model must be expanded when TLS automation, web application deployment, backups, firewall management, or tenant isolation are implemented. These subsystems are not present merely because they appear in a roadmap or design document.

This document does not make claims about Centmin Mod customer demographics, the prevalence of particular site categories, or the security of unrelated projects. Examples from technology-detection services do not establish compromise, customer composition, or causation. Claims about vulnerabilities must be tied to authoritative advisories, affected versions, reproducible evidence, and maintainer responses.

## 9. MIT licensing and clean-room provenance

StackAlign is licensed under the MIT License in the repository's `LICENSE` file. This comparison records architectural observations and independently stated StackAlign requirements.

The implementation must preserve that boundary:

- Do not copy Centmin Mod source code, scripts, patches, or substantial expressive documentation into StackAlign.
- Do not translate or mechanically reimplement another project's source as a substitute for independent design.
- Do not vendor external client or project source without a separate dependency and license review.
- Record third-party dependencies, versions, source locations, licenses, and required notices.
- Keep StackAlign-authored code and documentation clearly attributed.
- Treat compatibility requirements and public protocol behavior separately from copying another project's implementation.

A clean-room claim requires evidence of independent authorship and provenance. A comparison document alone does not establish that every implementation is clean-room or resolve every possible legal question. Distribution, linking, bundling, and derivative-work questions require case-specific review.

## 10. Implementation and acceptance gates

The following are required before StackAlign may claim the corresponding protection.

| Gate | Required implementation evidence | Required validation |
|---|---|---|
| Supported platform | Explicit EL9/EL10 and architecture detection; unsupported targets refuse | Disposable AlmaLinux/Rocky Linux 9 and 10 matrix |
| DNF-first package path | Package source selection and repository policy are explicit | Verify selected repo and package source on each target |
| Repository trust | Inventory, GPG checks, primary fingerprint pinning, no silent key import | Wrong key, missing key, extra primary key, subkey, unsigned RPM, and changed repo tests |
| Third-party opt-in | Explicit operator approval and recorded trust decision | Default-off and refusal tests |
| EOL policy | Publisher-aware lifecycle/advisory decision and exception record | Vendor backport vs truly unsupported package fixtures |
| Source-build exception | Immutable source, patch/build recipe, provenance and retirement metadata | Reproducible build and update/rollback test if implemented |
| Transaction history | Pre-change snapshot and secret-safe operation record | Interrupted-write and partial-transaction failure injection |
| Rollback | Recovery implementation for each mutating subsystem | Verify restored state and service health after induced failure |
| Security status | Distinguish detected, unknown, available, applied, verified | Scanner failure and false-negative boundary tests |
| Licensing | Dependency inventory and notices | Review all shipped and dynamically fetched components |

Until the relevant gate passes, describe the behavior as **designed** or **not implemented**, not as an enforced security control.

## 11. Current implementation status

At the time this document is authored:

- This file is documentation only.
- No package-policy enforcement is added by this change.
- No repository, key, EOL, source-build, scanner, or rollback runtime behavior is changed by this change.
- No production or disposable-host validation is claimed by this change.
- Existing README status remains authoritative for the overall project's maturity.

Future implementation work should be split into small reviewed changes, beginning with repository inventory and package-source policy. Do not combine this policy document with a broad installer implementation.

## 12. References

- Centmin Mod AlmaLinux/Rocky Linux support: https://community.centminmod.com/threads/131-00stable-140-00beta01-release-with-almalinux-rocky-linux-support.25572/
- Centmin Mod PHP security backports and upgrade recommendation: https://community.centminmod.com/threads/php-8-5-12-8-4-27-8-3-36-8-2-35-critical-security-updates-and-eol-php-7-4-8-1-backports.33134/
- Centmin Mod EOL PHP backport details: https://community.centminmod.com/threads/backport-php-8-2-35-security-fixes-to-php-7-2-7-3-eol-in-132-00stable.33146/
- Rocky Linux package signing and DNF verification: https://rockylinux.org/resources/gpg-key-info/
- Rocky Linux package signing and testing documentation: https://docs.rockylinux.org/guides/package_management/package_signing/
- AlmaLinux build and package-signing pipeline: https://wiki.almalinux.org/development/AlmaLinux-Build-System.html


## 13. FTP server and third-party transfer policy

**Policy status: specified; software enforcement unverified.** This section records the intended server behavior. It does not claim that StackAlign currently installs, configures, or secures an FTP service.

The server must retain its intended FTP server capability for ordinary client-to-server file transfers. A connected client may transfer files to or from the StackAlign server, subject to the FTP service's authentication, account, directory, permission, and logging controls.

**Reject FTP-to-FTP third-party transfers.** A client must not use the StackAlign FTP service as one endpoint in a server-to-server transfer to another FTP server (often called third-party FTP or FXP). This restriction must not be implemented by disabling the FTP service or indiscriminately blocking ordinary FTP client-to-server traffic.

**Enforcement boundary:** this is a software-level policy requirement derived from the firewall/security policy. It is not a verified firewall rule, and no firewall-only enforcement is claimed. The FTP daemon or a controlled software layer must explicitly refuse third-party transfer behavior while preserving ordinary client/server transfers. The exact daemon setting or enforcement mechanism remains unspecified until selected and verified against the actual server implementation.

Do not infer from this policy that FTPS or SFTP is enabled or disabled. They are separate protocols and require their own explicit service, authentication, and firewall decisions.

### Acceptance and verification requirements

Before describing this restriction as implemented or enforced, record evidence that:

1. A normal authenticated client can upload and download files to the StackAlign server.
2. A third-party FTP/FXP attempt that asks the StackAlign server to transfer directly to or from another FTP server is refused.
3. The refusal does not disable ordinary FTP service or block unrelated permitted client/server transfers.
4. The effective daemon configuration and relevant software logs show the refusal behavior.
5. The test records identify the daemon/version, configuration, commands, timestamps, and observed results.

Until those checks are run against the selected implementation, report the state as **SPECIFIED / UNVERIFIED**. Do not report PASS, firewall enforcement, or production protection based solely on this documentation.

<!-- Review comment: 2026-11-13T13:05:19-06:00; appended policy clarification only. Existing sections and wording above this point were retained. -->
<!-- Verification comment: README.md on main states that firewall management is not built and StackAlign is not production-ready. A GitHub code search scoped to ljrseals-dev/StackAlign for FTP/FTPS/SFTP/firewall terms returned no indexed matches at this review time. This confirms the documented status is unverified; it does not prove the absence of every possible implementation or establish runtime behavior. -->
