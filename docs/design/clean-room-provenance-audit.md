<!--
SPDX-License-Identifier: MIT
Copyright (c) 2026 Lewis James Seals Jr.
-->

# StackAlign clean-room provenance audit

**Audit status: IN PROGRESS — repository-level provenance is not yet established.**  
**Scope baseline:** main at 00982be62dccc42078a864193fbbc33c56fb1241  
**Audit method:** inspect StackAlign's own tracked files, Git history, declared dependencies, and attribution. Do not access or compare against GPL-licensed source repositories.

## Purpose

Record evidence relevant to StackAlign's independent authorship and MIT distribution. This is an engineering provenance review, not a legal opinion or a guarantee that no third-party rights are implicated.

## Clean-room boundary

- Do not open, download, clone, diff, or search source files from Centmin Mod or its GPL-licensed forks/mirrors.
- Do not translate or port code from GPL-licensed projects.
- Base implementation work on StackAlign requirements, independently written functional specifications, and official documentation for the interfaces and tools StackAlign uses.
- Similarity checks against GPL source are intentionally excluded. A line-count threshold is not a reliable copyright test and would contradict the no-access boundary.
- If a file's origin cannot be established, mark it UNVERIFIED and escalate; do not silently certify it or rewrite it to disguise its history.

## Initial repository findings

### License and repository identity

- The root LICENSE contains the MIT License and copyright notice for Lewis James Seals Jr.
- GitHub repository metadata identifies the project license as MIT.
- This confirms the repository's declared license, not the provenance or licensing of every individual file.

### Architecture

The inspected project uses a Bash CLI in bin/stackalign, separate modules under lib/, tests under tests/, and a TOML vendor metadata file. The inspected shell modules use the sa_ function namespace. These are useful indicators of a distinct design, but architecture and naming alone do not prove copyright independence.

### Source and test headers

The following inspected source/test files carry an SPDX MIT identifier and author attribution near the beginning:

- bin/stackalign, install.sh
- lib/config.sh, lib/fetch.sh, lib/history.sh, lib/render.sh, lib/repo.sh, lib/secret.sh, lib/service.sh, lib/tune.sh
- tests/test_cli.sh, tests/test_config.sh, tests/test_fetch.sh, tests/test_history.sh, tests/test_install.sh, tests/test_render.sh, tests/test_repo.sh, tests/test_secret.sh, tests/test_service.sh, tests/test_tune_math.py
- Makefile, .github/workflows/ci.yml, .gitea/workflows/ci.yml, vendor/versions.toml

A header is an attribution/metadata statement; it is not independent evidence of authorship. The audit must still establish provenance for the contents.

### Git history

The visible history includes an initial repository commit, a bulk project-file synchronization commit titled Sync project files via Zip2Git (12ec4d5), and subsequent incremental implementation/fix commits. The later history provides useful change records. The bulk synchronization point means the pre-import origin of every imported file cannot be reconstructed from the post-import commit history alone.

### Items requiring separate provenance review

- docs/StackAlign-complete-delivery.zip: bundled archive; contents and origin have not been independently inventoried in this audit.
- docs/Voice_Prompt_Injection_Defense_Guide_FBI.pdf: third-party document; author, source, copyright status, and redistribution permission need verification.
- 0001-fix-process-substitution-portability.patch and its copy under docs/: inspect authorship and whether the patch duplicates StackAlign-owned changes; record the original commit context.
- Research documents under docs/research/: identify any external text, diagrams, or copied material and add citations/attribution where required.
- External tools/actions and runtime dependencies: produce a dependency/license inventory. A source URL in vendor/versions.toml is not itself a license or provenance record.
- The bulk-import commit: recover the pre-import source/artifact history where available, including the archive used to create the repository.

## Audit register

| Area | Initial result | Required evidence / next action |
|---|---|---|
| Root MIT license | DECLARED MIT | Review all bundled and third-party materials individually |
| Core architecture | DISTINCT STRUCTURE OBSERVED | Keep as supporting context only; not a provenance conclusion |
| Shell source headers | PRESENT on inspected files | Establish origin from author records/specs and external-source notes |
| Test source headers | PRESENT on inspected files | Confirm independently authored test logic and fixture provenance |
| Bulk import | PROVENANCE GAP | Identify source archive, its contents, and pre-import history |
| Bundled ZIP | UNVERIFIED | Inventory archive members and their origin/licensing |
| Bundled PDF | UNVERIFIED | Establish author, source, license, and redistribution permission |
| Research documents | UNVERIFIED | Trace quoted/adapted material and cite sources |
| Patch files | PARTIALLY ATTRIBUTED | Reconcile patch metadata with corresponding commits and duplicate copy |
| Dependencies/actions | INCOMPLETE | Create a versioned third-party notices and license inventory |
| GPL-source comparison | NOT PERFORMED BY DESIGN | No access to GPL source under this clean-room process |

## Required next steps

1. Preserve the current audit baseline and identify the archive used for the bulk import.
2. Inventory the bundled ZIP without treating its presence as proof of authorship.
3. Verify the PDF's redistribution rights; remove or replace it if permission cannot be established.
4. Review research documents and patches for third-party text/code and attribution.
5. Inventory runtime, test, build, and CI dependencies with versions and license references.
6. Collect author/source/specification records for each implementation module, especially files first introduced by the bulk import.
7. Record findings with file paths and commit references. Do not label the whole repository SAFE until unresolved provenance items are closed.

## Decision rule

The current result is RISK DETECTED — provenance incomplete, not a finding that GPL material is present. No evidence in this initial review establishes that StackAlign contains copied GPL code. Equally, the architectural comparison and SPDX headers are insufficient to certify the entire repository as independently authored and MIT-compliant.


## Closed-loop provenance control (StackAlign-only)

The project will use a self-contained evidence loop. No neighboring installer, GPL codebase, fork, mirror, or competitor source is an input to this loop.

For each material implementation change, retain this chain:

1. **Requirement** — a StackAlign-owned requirement with an identifier, rationale, scope, and acceptance condition.
2. **Functional specification** — independently written behavior, inputs, outputs, failure modes, security boundaries, and non-goals.
3. **Implementation record** — file paths and commit(s) implementing that specification; identify the author and any external material consulted.
4. **Tests** — tests mapped to the requirement and failure modes; identify fixture origin and avoid copied third-party fixtures unless their license permits it.
5. **Verification** — exact CI run, runner, commit SHA, commands, and result. Keep CI evidence distinct from disposable-VM and production evidence.
6. **Release provenance** — source commit, build procedure, dependency lock/inventory, artifact digest, and included notices.

This is a traceability and change-control mechanism, not proof by assertion. Missing links remain OPEN/UNVERIFIED. A commit author field, SPDX header, passing test, or architecture diagram alone cannot establish copyright ownership.

### Required provenance record for each new or materially changed file

Record: path; first-introduced commit; last substantive change; responsible author; StackAlign requirement/spec ID; whether written from scratch, adapted, generated, or imported; external references consulted; third-party code/text/assets; applicable license/permission; tests; and review disposition. For imported files, preserve the original archive and its digest plus a member-level inventory. Do not rewrite history or remove attribution to make provenance appear cleaner.

### Closed-loop governance rules

- No implementation starts from a neighboring system's source, function names, file layout, or behavioral transcription.
- Official interface documentation may be consulted for DNF, RPM, systemd, Bash, GitHub Actions, and other tools; record the specific interface and version/date where material.
- Requirements and specifications must precede implementation where practical. Emergency fixes must receive a retrospective requirement/spec/test record before release.
- Every security-sensitive behavior needs positive and negative tests, including failure and rollback paths.
- Every release must be reproducible from a recorded source commit and declared inputs; unpinned or unverifiable inputs block a provenance-complete release.
- Third-party components retain their own licenses. StackAlign's MIT declaration does not relicense dependencies, bundled documents, copied snippets, or generated assets.
- A clean-room claim is limited to the process actually followed. It is not a guarantee of non-infringement and does not replace legal review.

## Additional evidence collected in this pass

### Workflow and CI evidence reconciliation

The current `.github/workflows/ci.yml` contains a comment saying the workflow has "never executed on a real runner." That statement is stale: GitHub Actions run 43351689173 is recorded as completed with conclusion SUCCESS for commit ea0f816df44372a658bfb1fc100d7142053e584a, on a pull_request event, with Ubuntu and AlmaLinux 9 jobs. The README also describes earlier CI runs. Correct the workflow comment in a separate documentation change; do not imply this historical run verifies the current branch or current workflow revision. CI success is not live-host or production validation.

### Research documents

- `docs/research/slave-web-node.md` is labeled design-only and implementation-pending. In the inspected text, it contains architecture and configuration proposals but no source citations. Record it as StackAlign design material with external influence/source review still required; absence of citations is not proof that no external material was used.
- `docs/research/workload-registry.md` describes workload values as assumptions and cites `lib/tune.sh` as implementation context. Its numerical assumptions and policy recommendations should be traceable to StackAlign requirements or explicitly cited external sources. No external citations are present in the inspected text.

### Portability patch

The root patch and `docs/0001-fix-process-substitution-portability.patch` are the same Git blob (bf9e86ff0cbbe037d246a7f35883b1d747ae012b). The patch carries a From line, author identity, date, subject, and a statement that T1-T28 passed. Those are useful attribution claims, not independent proof of authorship or test execution. The file-history query surfaced merge commit 9600b1734ad3ccbb7923a87a7f364d0e9a4d0471 for the patch path; recover the original patch-creation context and verify the referenced test run before treating the claims as substantiated. The duplicate copy should be documented as one artifact, not two independent works.

### Binary evidence limitations

The tracked ZIP `docs/StackAlign-complete-delivery.zip` has blob SHA 56cd6a7e3534f3f6a19cc9502f948d49f7f3219d and size 58,912 bytes. The tracked PDF `docs/Voice_Prompt_Injection_Defense_Guide_FBI.pdf` has blob SHA ede805f48f6069f09c2bf33cdc3fefbf72bed660 and size 12,272 bytes. The available GitHub text-file retrieval interface rejects binary responses, so neither artifact's bytes, archive members, PDF metadata, nor embedded content were inspected in this pass. Both remain UNVERIFIED. Do not claim an archive inventory or redistribution permission until the actual bytes and provenance are examined.

### Commit-signature observation

The audit branch commit 172422dcc7743d2663fb285fb848b10f986e2276 is reported by GitHub as unsigned. This does not determine copyright ownership, but release governance should decide whether signed commits/tags are required and enforce that policy consistently. Historical commits have mixed verification states; do not infer that unsigned means unauthorized or that signed means the content is independently authored.

## Updated disposition

The self-contained traceability model is now defined, but it has not yet been applied file-by-file. Current status remains **RISK DETECTED — provenance incomplete**. In particular, bulk-import origin, ZIP/PDF contents and rights, research-source history, patch creation/test evidence, and third-party dependency/action inventory remain unresolved.


## Repository-only audit pass 2 — source, build, packaging, and CI

**Reviewed ref:** main at 00982be62dccc42078a864193fbbc33c56fb1241, except where explicitly noted. This pass inspected the tracked text files listed below. It did not access any neighboring installer source.

### Platform scope and support evidence

The project owner's stated intended deployment target is AlmaLinux and Rocky Linux 9/10. The current README describes the scope more broadly as "EL-family Linux on x86_64"; the CI workflow shown on main has an AlmaLinux 9 container job and an Ubuntu 24.04 CI job. No Rocky Linux or EL10 CI evidence was established in this pass. Ubuntu is explicitly described by the README as a CI environment, not a supported deployment target. Narrow the product requirement and compatibility matrix to the intended distributions/releases, and do not infer support from the generic EL-family label. This platform distinction is a StackAlign scope decision, not evidence of authorship or provenance.

### File-level evidence register — pass 2

| Path | Observed evidence on main | Provenance / license disposition |
|---|---|---|
| README.md | Declares experimental status, feature limits, EL-family x86_64 intent, CI history, and MIT license | Project documentation; author/source history still needs per-file origin record |
| LICENSE | Contains MIT text and 2026 copyright notice | Declared project license only; does not resolve bundled or third-party materials |
| Makefile | Runs Bash syntax checks, optional ShellCheck, shell suites, and Python 3 tuner tests | Build/test orchestration; ShellCheck is silently optional only with an explicit message; dependency versions and license inventory remain open |
| install.sh | Refuses while release SHA is PLACEHOLDER; uses curl, sha256sum, awk, tar, mktemp | Not currently runnable as a release installer; tools and archive handling need dependency/version inventory and independent tests |
| bin/stackalign | Dispatcher documents many commands as stubs; sources project modules | Authorship still requires requirement/spec/commit/test mapping; comments refer to a master prompt not present in this repository snapshot |
| lib/fetch.sh | HTTPS-only curl fetch, temporary staging, SHA-256 verification, GPG primary-key fingerprint inspection | SHA-256 is integrity, not publisher identity; source history and test provenance remain open |
| lib/repo.sh | DNF/RPM repository helpers; imports a fetched key after primary fingerprint validation | Package-manager behavior is not proof of authorship; map behavior to M3 requirements and test evidence |
| tests/test_install.sh | Uses fake curl and generated tar fixtures; invokes Python 3 to create hostile archive fixtures | Fixture generation is test code; establish fixture origin and ensure the test interpreter/version is recorded |
| tests/test_fetch.sh | Fake curl/GPG fixtures exercise failover, checksum, key parsing | Fixture origin and complete test-run evidence remain open |
| tests/test_repo.sh | Fake DNF/RPM/curl/GPG executables; no real package manager intended | Mock success does not establish live DNF/RPM behavior |
| vendor/versions.toml | Nginx/PHP/MariaDB versions listed; SHA-256 and GPG fingerprints are literal TO_BE_FILLED placeholders; tested_matrix arrays are empty | Not a verified vendor manifest; no release integrity/authenticity claim may rely on these placeholders |
| .github/workflows/ci.yml | Main contains a stale "WRITTEN, NOT RUN" comment despite recorded historical CI success; uses actions/checkout@v6 with pin status marked TO_BE_VERIFIED | Third-party action provenance/version/license must be inventoried; do not treat tag text as immutable pin |
| .gitea/workflows/ci.yml | Exact same Git blob as .github/workflows/ci.yml (SHA 55108d2a054d734c9cce5b69b1ef0042a9b73c81) | One duplicated artifact, not independent authorship; Gitea compatibility/execution has not been established |

### Specific evidence and defects recorded

1. **Release bootstrap is intentionally disabled.** install.sh has VERSION=0.0.0-dev and EXPECTED_SHA256=PLACEHOLDER, and explicitly exits before network access. README independently says installation is not yet built. This is consistent with the declared experimental status; do not describe StackAlign as an operational LEMP installer.
2. **Vendor metadata is not release-ready.** All three vendor SHA-256 and GPG fingerprint values are placeholders, and all tested_matrix arrays are empty. The URLs and version strings are declarations, not verified provenance, authenticity, or compatibility evidence.
3. **Third-party CI action remains unverified.** actions/checkout@v6 is referenced by both workflow copies, while the file itself labels the version TO_BE_VERIFIED. No immutable commit SHA or license inventory was established in this pass.
4. **Workflow duplication needs an explicit policy.** The .gitea and .github workflow files have the same blob SHA. The shared file content uses GitHub Actions conventions and includes an actions/checkout reference; no Gitea runner execution/compatibility evidence was inspected. Do not imply both providers execute it.
5. **Main vs audit-branch workflow discrepancy.** The main-branch .github/workflows/ci.yml still contains the old "WRITTEN, NOT RUN" comment. PR #11 changes the GitHub workflow comment to accurately describe historical run 43351689173. The .gitea copy on main remains byte-identical to the stale main GitHub workflow. The PR change is documentation-only and does not establish a new test result.
6. **PR #11 CI evidence.** GitHub reports a completed-success workflow run (ID 43357065241) associated with PR #11 head ec0df648e3b82efde3ba5f441965affd9f7c8879. This is evidence for that exact commit's CI run only; it is not EL10/Rocky coverage, a disposable VM, or a live installation.
7. **Patch provenance remains unresolved.** The patch's embedded From commit is a8338151a3884ea395ed687d8e80df930223d97c. GitHub's repository commit endpoint returned "No commit found for SHA" for that identifier. The later merge commit 9600b1734ad3ccbb7923a87a7f364d0e9a4d0471 includes the patch and a delivery note describing a ZIP-based delivery plus a portability fix. This does not prove the embedded commit never existed elsewhere; the originating repository/artifact and the claimed T1-T28 test run remain unverified. The ZIP still cannot be inventoried through the text-only retrieval path.
8. **Prompt-origin references need recovery.** install.sh and bin/stackalign contain "master prompt v8 Part III" references, but that source specification is not present in the inspected tracked tree. Recover the prompt/specification and its date/version, preserve it as provenance evidence, and map its requirements to code/tests. Do not treat a prompt reference as proof of independent authorship.

### Next evidence required

- Recover the exact master prompt v8 Part III and the source archive used at the bulk import; hash both and inventory the archive member-by-member.
- Resolve the patch's embedded commit and test claim using original author-side records or the originating artifact; do not substitute a newly run test for historical proof.
- Inventory versions, immutable identities, and licenses for actions/checkout, Bash, Python, ShellCheck, curl, GNU tar/coreutils, GPG, RPM, DNF, and all runtime/test dependencies as applicable.
- Establish whether the Gitea workflow is intended to run; if so, validate it on a Gitea runner or remove the misleading duplicate through a separately reviewed change.
- Define and test the exact AlmaLinux/Rocky 9/10 support matrix. Do not mark a distribution/release supported from an Ubuntu job or an AlmaLinux 9-only container job.
- Keep the ZIP and PDF UNVERIFIED until their bytes, contents, origin, and redistribution rights are actually examined.

**Pass 2 disposition:** More implementation and packaging evidence is now recorded, but the file-level provenance loop is not closed. Status remains **RISK DETECTED — provenance incomplete**. No conclusion is made that GPL material is present or absent.
