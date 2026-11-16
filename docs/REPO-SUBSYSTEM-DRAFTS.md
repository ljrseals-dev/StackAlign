# Repository subsystem contracts (draft)

**Status:** Draft contracts and synthetic fixtures only. This change does not implement a repo plan/apply engine, audit writer/reader, mirror probing/ranking, or doctor integration. The existing `lib/repo.sh` remains the current repository setup/inventory module. These artifacts must not be interpreted as production support or permission to mutate host repositories.

## Scope and compatibility

The plan schema is `stackalign.repo.plan/v1`; audit records are `stackalign.repo.audit/v1`; mirror rankings are `stackalign.repo.mirrors.rank/v1`. Incompatible changes require a version bump. A JSON Schema validates record shape only; canonical hashing, file preconditions, hash-chain continuity, filesystem safety, and transaction semantics require separate runtime validation.

## Plan file and hash

See [repo-plan.v1.schema.json](../lib/schemas/repo-plan.v1.schema.json).

Canonical plan bytes are UTF-8 without BOM, compact JSON, object keys sorted by UTF-8 byte order, and deterministic JSON number formatting. The `plan_sha256` member is omitted before hashing; the hash is SHA-256 of those canonical bytes. `created_at` is included, so generating a new plan at a different instant intentionally changes its digest. Apply must verify the supplied confirmation hash and recheck every precondition immediately before mutation.

Additional semantic checks not expressible by the schema:
- `repo_files_sha256` must cover the complete set of files the plan relies on; paths must be canonical, absolute, non-symlink regular files within approved repo-config locations.
- A mirror action targeting `baseurl` or a literal `mirrorlist` requires a valid `url`; `metalink` destinations must not carry a literal URL unless a future schema version defines that behavior.
- `vault-enable` requires a CentOS 7 EOL host, explicit operator acknowledgement, and an approved Vault URL. It is never inferred.
- Every action must resolve to exactly one existing repo stanza and must preserve unrelated stanzas, comments, and unknown directives.
- `expected_post_sha256` must exactly cover the files predicted to change; no unlisted file may be changed.
- A plan with no effective change should use `noop` rather than an empty action list.

## Audit JSONL

See [repo-audit.v1.schema.json](../lib/schemas/repo-audit.v1.schema.json).

The stream is UTF-8 JSON Lines: one complete object per newline-terminated line, no BOM or blank lines. Writers must serialize a complete record before opening the journal, use an exclusive lock, append with O_APPEND, write one line, and fsync. A partial trailing line is corruption, not a valid record.

Each record's `prev_line_sha256` hashes the exact previous serialized line bytes excluding its trailing LF. Sequence starts at 1 and increments by one. Hash chaining detects accidental or malicious edits only when the chain head is independently trusted; it is not a digital signature and does not prevent truncation of the tail.

**Pruning correction:** append-only history and rewriting the live stream to remove old lines are incompatible. V1 therefore does not authorize in-place pruning/compaction. A future archive operation must atomically preserve the original stream, produce a separately verifiable archive, and append a linked archive/prune marker without renumbering existing records. Retention is advisory until that protocol is implemented. The `prune` evidence shape is reserved, not an authorization to prune.

Redaction happens before serialization. Query parameters whose names match key/token/password/sig/credential are removed; URL userinfo is removed; authorization headers and machine-id/raw SSH socket values are never recorded. A second validation pass rejects residual secret-like values. Do not log full command environments, key material, or credential-bearing URLs.

Schema validation is per line. Reader validation additionally checks sequence continuity and the previous-line digest. Readers fail closed by default; an explicit corrupt-read override must itself be auditable when the journal is writable. Never treat journal file hashes as authoritative current disk state.

## Mirror ranking

See [repo-mirrors-rank.v1.schema.json](../lib/schemas/repo-mirrors-rank.v1.schema.json).

Hard exclusions precede scoring: unreachable, missing metadata, stale metadata, unverified signature, and policy deny-list entries are never scored. Only eligible mirrors participate in per-run min/max normalization. The default v1 score is:

```
score = 0.50 * norm_latency
      + 0.30 * norm_freshness
      + 0.20 * norm_preference
      - 0.25 * instability
```

Latency and freshness normalize to 1 for the best value and 0 for the worst; if all eligible values are equal, the normalized value is 1. Metalink preference is preference/100, or 0 when unavailable. Instability is failures/history_window, or 0 when there is no history. The result is clamped to [0,1] after applying the penalty. Weights for latency, freshness, and preference must sum to 1 within 1e-9; instability weight is independent.

Sort by score rounded to six decimal places descending, latency ascending, metadata age ascending, preference descending, then URL bytewise ascending. Use fixed-point/integer arithmetic for the comparison path where practical; do not rely on locale-sensitive sorting. Output ordering must not depend on input array order.

A fallback plan requires at least two eligible candidates so it can avoid selecting the current source. It may select only a ranked candidate, carries the probe evidence into the plan, and never automatically changes a repo file. Moving from metalink to baseurl additionally requires explicit policy allow-list membership.

## Doctor repo section

`stackalign doctor` gains a read-only repo section; `stackalign doctor --section repo` runs only this section, and `--json` emits `stackalign.repo.doctor/v1`. Stable check IDs are append-only and must never be renumbered.

| ID | Check | PASS | WARN | FAIL | SKIP |
|---|---|---|---|---|---|
| REPO-001 | Distribution support | Supported family/version | — | Unsupported target | — |
| REPO-002 | Package backend | dnf/yum executable | Unusual version | Missing backend | — |
| REPO-003 | Repo syntax | All files parse | Parse warnings | Parse error | No repo files |
| REPO-004 | Enabled repos | At least one enabled | Zero enabled repos | — | — |
| REPO-005 | Metadata reachability/freshness | All reachable and fresh | Reachable but stale | Any enabled repo unreachable | Network explicitly disabled |
| REPO-006 | Key verification | All enabled-repo keys verified | Unverifiable key only for disabled repo | Enabled repo has unverified key | — |
| REPO-007 | EOL handling | Non-EOL or correctly configured Vault | EOL host without Vault | Vault on non-EOL host | — |
| REPO-008 | Journal hygiene | Readable valid journal, recent entry | Missing/old journal | Corrupt/unreadable journal | Journal disabled |
| REPO-009 | Backup integrity | All retained backups verify | Missing manifest | Hash mismatch | No backups |

Each check emits exactly one status from PASS, WARN, FAIL, SKIP and includes stable `id`, `title`, `details`, and optional `remediation_hint`. A hint is advisory only and is never executed. REPO-006 delegates to the same key-verification implementation used by `repo keys verify`.

The repo section is read-only. It must not refresh metadata unless a future explicit `--refresh-metadata` option is supplied. Network checks are bounded by a per-repo timeout (default 10 seconds). The section reports into the doctor aggregate rather than exiting independently: FAIL => 2; WARN => 0 normally and 2 under `--strict`; internal error/schema violation => 3. Existing aggregate doctor severity rules remain authoritative.

## Fixture inventory

The `tests/fixtures/` directory contains synthetic DNF/YUM output, a metalink snapshot, probe results, an EPEL repo file, synthetic key inventory, and expected status JSON. No fixture is evidence of a real host, key, mirror, or VM run.

## Not implemented by this contract-only change

- Repo plan generation, canonical JSON hashing, plan application, locking, backups, rollback, or audit writing/reading.
- Real GPG verification or mirror probes/ranking.
- CLI wiring, doctor integration, install/update preconditions.
- CentOS 7 Vault support, APT support, or disposable-VM validation.

Those require separate implementation and test work. Until then the repo subsystem remains **DRAFT / UNVERIFIED**.
