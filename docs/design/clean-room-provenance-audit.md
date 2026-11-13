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
