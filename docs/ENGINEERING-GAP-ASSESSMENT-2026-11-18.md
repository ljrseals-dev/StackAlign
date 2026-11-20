# StackAlign engineering gap assessment against Centmin Mod

**Inspection date:** 2026-11-18 (UTC)  
**Assessment type:** Initial, read-only repository reconnaissance  
**StackAlign baseline:** `ljrseals-dev/StackAlign`, default branch `main`, commit `ca069223d7ba5ac071d3198508d47f172ad49009`  
**Centmin Mod baseline:** `centminmod/centminmod`, default branch `master`, commit `4e7aec8585c6ad169773d1a77df17f560e4e0d71`  
**Additional Centmin reference:** `141.00beta01`, commit `1d1146eb17b82b246a15e49a4addca92f8b748d4`  
**Working-tree status:** Not available through the GitHub read API; no local checkout was used.  
**Validation performed for this assessment:** GitHub repository metadata, branch/tree/commit reads, and source/document inspection. No shell commands, tests, package operations, or host changes were executed for this PR.

## 1. Access and baseline

Both repositories were publicly readable through GitHub.

| Item | StackAlign | Centmin Mod |
|---|---|---|
| Repository | [ljrseals-dev/StackAlign](https://github.com/ljrseals-dev/StackAlign) | [centminmod/centminmod](https://github.com/centminmod/centminmod) |
| Default branch | `main` | `master` |
| Inspected commit | `ca069223d7ba5ac071d3198508d47f172ad49009` | `4e7aec8585c6ad169773d1a77df17f560e4e0d71` |
| License metadata | MIT | GPL-3.0 |
| Primary language metadata | Shell | Shell |
| Repository tree | 100% response, not truncated | 100% response, not truncated |

The Centmin Mod default-branch README identifies the project as a shell-menu Nginx/LEMP installer and describes unattended root installation. Its README text still contains older release-transition guidance (131 stable / 140 beta), while the branch listing contains newer `132.00stable` and `141.00beta01`. For current feature inspection, this assessment therefore records both the default-branch snapshot and the newer 141 beta commit rather than treating the README's release paragraph as authoritative current branch selection. The 141 beta commit is dated 2026-11-18 and its message concerns AlmaLinux Kitten kernel security baselines; it is a real branch reference, not a claim that every Centmin deployment should use beta code.

Centmin Mod's repository metadata reports GPL-3.0; StackAlign reports MIT. This comparison is behavioral and architectural. This PR adds no Centmin Mod source and does not copy upstream implementation code. Any future adaptation requiring copied code needs a separate provenance and licensing review.

### StackAlign source map

The inspected StackAlign tree contains a Bash CLI (`bin/stackalign`), installer (`install.sh`), shell libraries under `lib/`, Nginx templates, fixtures and shell/Python tests, Makefile-driven lint/test targets, and GitHub/Gitea CI workflows. Relevant modules include:

- Configuration and secrets: `lib/config.sh`, `lib/toml.sh`, `lib/secret.sh`
- Platform/package/release: `lib/repo.sh`, `lib/repo_cache.sh`, `lib/fetch.sh`, `lib/verify.sh`, `lib/update.sh`
- LEMP/hosting/site: `lib/lemp.sh`, `lib/hosting.sh`, `lib/site.sh`, `lib/render.sh`
- Database/backup/TLS: `lib/db.sh`, `lib/backup.sh`, `lib/tls.sh`
- Host operations: `lib/service.sh`, `lib/firewall.sh`, `lib/egress.sh`, `lib/sftp.sh`, `lib/security.sh`
- Tests: `tests/test_*.sh`, `tests/test_tune_math.py`

This is a tree-level architecture map, not a complete call-graph or end-to-end workflow trace.

## 2. Executive assessment

StackAlign's key product strengths are its deliberately narrow EL9 x86_64 LEMP apply scope, plan-before-apply approach, distribution-package preference, read-only diagnostics, guarded mutating operations, and explicit documentation of mock-test versus real-host evidence. Its current README explicitly says it is experimental and not production-ready. That limitation is important and should remain visible.

The main maturity gap is not simply missing feature count. It is that multiple useful subsystems are currently diagnostics, inventory, planning, or narrowly gated operations rather than fully validated operator lifecycles. Centmin Mod is substantially broader in its menu, addons, version-management, and WordPress-oriented tooling, but that breadth should not be interpreted as a requirement to reproduce its architecture or defaults.

### Evidence-backed current-state summary

| Area | StackAlign evidence at baseline | Initial classification |
|---|---|---|
| CLI and module architecture | `bin/stackalign`, `lib/*.sh`, shell test suites | Implemented foundation; workflow completeness varies |
| LEMP bootstrap | README documents distro-packaged Nginx, MariaDB and PHP-FPM on EL9 x86_64, loopback endpoint | Narrow implemented beta; mock-tested; live host validation not established |
| Configuration | `lib/config.sh` parses INI as data and requires config version 1; README/docs describe schema validation as incomplete | Partial implementation / validation gap |
| Package/repository management | Repo audit/cache and update modules; README says real repository/key lifecycle and live DNF rollback are unverified | Partial implementation / integration gap |
| Nginx/Apache site handling | `lib/site.sh` inventories standard vhost paths and runs syntax diagnostics; site create/remove/isolation remain blocked | Read-only diagnostics implemented; lifecycle gap |
| PHP-FPM / tenant isolation | README and `docs/BETA-SCOPE-AND-HOSTING.md` describe shared default `www` pool and distinguish admin-managed vhosts from mutually untrusted users | Intentional gated capability; isolation not established |
| Database | Read-only server/schema/account inventory and plan/apply database creation; user grants and destructive drop blocked | Partial lifecycle |
| Backup | `lib/backup.sh` supports logical mysqldump and physical MariaBackup creation/list/integrity checks; restore and SQL restoreability remain gated | Backup creation partial; restore/recovery gap |
| TLS | Client inventory, certificate status, scheduler preflight, and Certbot HTTP-01 plan-only path; issuance/renewal/deployment remain blocked | Diagnostics/planning implemented; lifecycle gap |
| Release/update trust | Signature-verification foundation exists; README says installer/update integration incomplete | Partial implementation / supply-chain integration gap |
| Firewall/egress | Opt-in egress policy and firewall support described; README says non-persistent and real kernel/network behavior unvalidated | Partial / integration gap |
| CI | `.github/workflows/ci.yml` runs lint, headers and tests on Ubuntu plus AlmaLinux 9 userland | Automated test coverage exists; not full OS/systemd/SELinux/firewall validation |
| Performance/resource support | Tuner and measurement scripts exist; README limits claims and records assumptions | Measurement gap; no comparative benchmark conclusion |

### Immediate safety and product-boundary observations

1. StackAlign explicitly warns against production use. This assessment does not change that status.
2. TLS issuance and renewal are correctly gated in the inspected documentation because protected secret transport and crash-safe certificate/key deployment are not yet established.
3. Backup creation must not be confused with a tested restore. The logical backup verifier's documented gzip-integrity check is not SQL restoreability.
4. A shared PHP-FPM pool or an extra pool alone does not prove mutually untrusted tenant isolation.
5. Centmin Mod's README describes a root-run unattended installer and a 4 GB minimum memory requirement for the cited installer paths. That is an upstream product constraint, not a StackAlign requirement or an equivalent benchmark.
6. No evidence in this read-only pass establishes a current StackAlign P0 defect. That is not a clean security audit: threat-model testing, hostile-input execution, and host integration remain unperformed.

## 3. Comparison baseline and upstream capabilities

The inspected Centmin Mod default branch and 141 beta tree show a broad shell-based LEMP product with modules for Nginx installation/configuration/vhosts/upgrades, PHP configuration/upgrades, MariaDB installation/upgrades, data management, and WordPress tooling. The 141 beta tree includes, among other paths, `centmin.sh`, `inc/nginx_addvhost.inc`, `inc/nginx_backup.inc`, `inc/nginx_install.inc`, `inc/nginx_upgrade.inc`, `inc/php_configure.inc`, `inc/php_upgrade.inc`, `inc/mariadb_install*.inc`, `inc/mariadb_upgrade*.inc`, `inc/datamanager.inc`, and `tools/nvwp.sh`.

The paths prove that implementation files exist at the selected commit; they do not by themselves prove that every menu option works on every OS/release or that every feature is recommended for StackAlign. Detailed execution tracing and supported-release validation are required before any specific feature is classified as a verified upstream behavior.

The Centmin Mod README's own release guidance and current branch list conflict in freshness. The comparison therefore uses:
- `master` for the default-branch repository snapshot;
- `141.00beta01` for a current named development branch with a pinned commit;
- the current Centmin official README for product-level install/scope claims.

No Centmin code is run or installed as part of this work.

## 4. Initial capability gap matrix

Statuses below are deliberately conservative. "Unknown" means the relevant workflow has not yet been traced sufficiently; it does not mean missing.

| ID | Category / operator outcome | StackAlign evidence | Centmin evidence | Status | Priority / disposition |
|---|---|---|---|---|---|
| A-01 | Supported-host preflight and repeatable bootstrap | EL9 x86_64 LEMP apply path documented; mock-tested; live host not validated | Root unattended installer documented; branch/release-specific OS requirements | Partial / validation gap | P1 — verify in disposable EL9 VM before expanding OS matrix |
| C-01 | Nginx vhost create/update/remove | Read-only inventory and syntax doctor; lifecycle blocked | Nginx vhost module present in 141 tree | Verified StackAlign gap in lifecycle breadth | P1 — implement safe single-admin vhost lifecycle only after staged-write contract |
| D-01 | PHP-FPM pool ownership and isolation | Shared default pool; independent-user isolation explicitly unproven | PHP configuration and vhost modules present | Partial / intentional gate | P1 — do not claim tenant isolation; test identity/socket/filesystem boundaries first |
| E-01 | Database/user lifecycle | Read-only user inventory and database create; grant/drop blocked | MariaDB install/upgrade and database menu modules present | Partial | P1 — least-privilege application user creation and rotation; keep destructive drop gated |
| F-01 | TLS issuance and renewal | Client discovery/status/plan; issuance and scheduler changes blocked | Centmin tree contains ACME-related tooling (specific issuance path not traced in this pass) | Partial / unknown upstream lifecycle details | P1 — secure secret channel, staging issuance, atomic pair activation, renewal failure tests |
| L-01 | Backup restore and disaster recovery | Backup creation/list/integrity; restore blocked | Data manager and backup tooling present | Verified StackAlign lifecycle gap; upstream behavior not yet tested | P1 — restore into disposable clean target and prove data/ownership recovery |
| J-01 | Schema validation and atomic config updates | INI parser exists; schema validation described as incomplete | Persistent custom config documented in Centmin README | Partial | P1 — schema validation, atomic writer, ownership/mode and operator-edit preservation |
| K-01 | Upgrade rollback and crash recovery | Update transaction design exists; live DNF transaction/rollback unverified | Nginx/PHP/MariaDB upgrade modules exist | Partial / validation gap | P1 — disposable VM failure-injection before widening apply support |
| M-01 | Actionable diagnostic and support evidence | Doctor, status, inventory, and subsystem diagnostics exist | Broad menu and helper scripts present | Partial | P2 — consistent operation IDs, redaction, structured diagnostics |
| N-01 | Measured low-resource sizing and workload performance | Tuner assumptions and measurement scripts documented; no comparative benchmark established | Centmin README cites 4 GB for listed installers | Unknown / measurement gap | P2 — publish reproducible StackAlign measurements; no inferred parity |
| O-01 | Automated regression and release controls | Makefile lint/headers/tests; Ubuntu + AlmaLinux 9 CI | README shows workflow badges for multiple EL families; branch tree has extensive tooling | Partial / coverage gap | P1 — add disposable full-system tests for supported EL9 lifecycle |

This matrix is a first-pass shortlist, not the exhaustive A–O inventory requested by the engineering prompt. Platform-specific details, actual Centmin menu call paths, and complete StackAlign workflow traces remain backlog items.

## 5. Prioritized implementation program

### P0 — stop-ship safety issues

No P0 issue is confirmed by this read-only inspection. The following areas remain high-risk verification targets and must be escalated if testing finds data loss, credential exposure, unsafe root execution, or failed recovery:
- TLS secret handling and certificate/key activation.
- Backup restore and overwrite/destructive target validation.
- Privileged configuration writes and interrupted package operations.

### P1 — core lifecycle reliability

1. **Restore verification vertical slice (recommended first).** Trace the existing backup and restore CLI paths; document exact preconditions and destructive boundaries; add isolated fixtures/fake-tool tests for target validation and failure cleanup; implement only a non-destructive restore plan or disposable-target restore where the existing contract permits. Do not enable live restore to an existing datadir without a pre-restore snapshot and verified recovery.
2. **Configuration schema and safe writer.** Define supported keys/types/precedence; reject unknown or malformed values; stage writes in the destination filesystem; preserve intended ownership/mode; detect operator edits and symlink targets; test interrupted writes.
3. **Single-administrator vhost lifecycle.** Start with add/update plan and staged config validation; reject unsafe domains/paths; preserve unmanaged includes; run `nginx -t` against staged configuration before activation; do not claim tenant isolation.
4. **Application database principals.** Add per-application database users and least-privilege grants through a protected credential channel; test quoting, account host scope, duplicate/rerun behavior, and secret redaction. Keep drop blocked until backup/restore acceptance exists.
5. **TLS renewal/deployment safety.** Implement a secret channel that avoids argv/log exposure, stage candidate certificates, validate chain/SAN/key match, activate certificate/key as one versioned release pointer, then validate/reload and recover on failure. Add staging ACME tests before live issuance.
6. **EL9 full-system validation.** Run the documented LEMP lifecycle in disposable AlmaLinux/Rocky Linux 9 VMs with systemd, package repositories, service health, reboot persistence, and failure injection. Container CI must remain labeled as container/userland validation.

### P2 — maintainability and measured operations

- Stable structured diagnostic output and automatic secret redaction.
- Explicit support matrix and provenance of package/version pins.
- Measured memory and latency baselines, including representative PHP/database workloads.
- Log rotation, retention and operator-visible health summaries where the current product scope warrants them.

### P3 — optional parity only after core lifecycle gates

- Additional runtimes, cache services, authoritative DNS, mail hosting, dashboards, or broad WordPress automation.
- Centmin Mod migration tooling as a separate read-only inventory and rehearsal deliverable.
- Source-build options only if measured requirements justify the maintenance burden over distro packages.

## 6. Dependencies and critical path

```text
test harness + disposable EL9 VM
        |
configuration/path/secret contracts
        |
staged file writer + operation state/locking
        |
+-------------------+--------------------+
|                   |                    |
backup restore   vhost lifecycle    database principals
|                   |                    |
+-------------------+--------------------+
                    |
           system integration checks
                    |
      release/update + recovery acceptance
                    |
          measured benchmark / support claims
```

TLS has an additional dependency on protected credential transport and atomic certificate/key deployment. Independent-user isolation has a separate critical path through Unix identity, PHP-FPM pool/socket ownership, filesystem access, and kernel/service boundaries. Neither should be inferred from vhost support.

## 7. First-slice contract: backup restore safety

**Problem:** StackAlign has backup creation and integrity-checking behavior, but its README and status documentation state that restore is gated. A backup that has not been restored is not a verified recovery mechanism.

**User-visible outcome:** Operators can inspect a restore plan and, after acceptance tests, restore a backup only into a clearly identified disposable/new target under explicit authorization. Existing data is never silently overwritten.

**Scope:**
- Trace `bin/stackalign` restore routing and `lib/backup.sh` restore helpers before changing code.
- Record supported logical/physical backup formats and their version compatibility.
- Validate backup artifact path, ownership, permissions, integrity, and completeness.
- Validate target path and reject symlinks, traversal, root, empty, or unexpected targets.
- Require a new/empty target or an explicit, separately reviewed replacement contract.
- Ensure failures preserve source backups and retain actionable diagnostics.
- Keep production-host restore out of scope.

**Acceptance criteria:**
- Unit tests reject unsafe, symlinked, malformed, incomplete, and incompatible inputs.
- Fake-tool tests prove argv boundaries and ensure secrets are not passed in command-line arguments.
- Failure injection covers missing utility, corrupt archive, failed prepare/import, disk/write failure where practical, and interrupted execution.
- A disposable EL9 integration test restores to a clean target and verifies database contents, ownership, permissions, and service health.
- Rerun and concurrent invocation behavior are explicit and tested.
- Documentation states exactly which format/platform versions were tested and which recovery claims remain unverified.

**Authorization:** This slice can begin with source inspection, plan-only behavior, and unprivileged/fake-tool tests. A real database restore requires an explicitly disposable VM and explicit authorization for system-changing integration work. No production system is authorized.

## 8. Validation and limitations

- GitHub metadata/tree/source reads: completed for the pinned commits above.
- Full StackAlign workflow call-graph tracing: not completed.
- Full Centmin Mod menu/addon execution tracing: not completed.
- `make lint`, `make headers`, `make test`: NOT RUN for this documentation-only PR.
- Disposable VM/container integration: NOT RUN.
- Live package manager, systemd, firewall, SELinux/AppArmor, DNS/ACME, database restore, reboot, and performance tests: NOT RUN.
- Working-tree cleanliness: unavailable through the GitHub read API.
- No production systems were accessed or modified.

A command's historical CI result is not reused as validation of this assessment or of any future code change. The CI workflow currently defines Ubuntu and AlmaLinux 9 userland jobs; it does not itself prove full host integration.

## 9. Next actions

1. Review this baseline and confirm the initial priority ordering.
2. Execute the backup/restore source trace on current `main` and update this report with exact symbols, line ranges, and tests.
3. Implement the smallest safe restore-plan/test increment in a separate PR if the source trace confirms the stated gap.
4. Schedule disposable EL9 full-system acceptance before making production-readiness claims.
5. Re-pin this assessment whenever either repository baseline changes materially.

---

**Decision:** Adopt Centmin Mod as a capability reference only. Preserve StackAlign's Bash architecture, distro-package strategy, guarded operations, low-resource intent where measured, and honest experimental status. Close verified operator-lifecycle gaps in small, tested increments; do not pursue feature-count parity.
