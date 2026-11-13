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
