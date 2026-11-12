# Workload registry design

**Status: design only; lib/tune.sh and tests do not exist in the repository yet.** The registry is data consumed by one tuning engine. It is not a separate tuner or workload-specific algorithm.

## Proposed registry fields

| Workload | child_rss_mib | worker_memory_mib | redis_sessions_mib | redis_cache_mib | min_profile | min_ram_mib | worker_db_connections |
|---|---:|---:|---:|---:|---|---:|---:|
| plain | 30 | 0 | 0 | 0 | lean | 512 | 0 |
| wordpress | 70 | 0 | 0 | 0 | lean | 1024 | 0 |
| laravel | 60 | 0 | 0 | 0 | lean | 1024 | 0 |
| xcart | 90 | 128 | 32 | 64 | standard | 2048 | 4 |

Every numeric value is an initial assumption, not a measurement. Child RSS, worker footprint, Redis allocation, and worker connection count require M2b measurement. Redis values are defaults only; explicit user configuration overrides them.

The registry's X-Cart min_profile=standard and min_ram_mib=2048 are policy recommendations. They generate warnings and prominent doctor findings, not automatic refusal. If the requested profile is below the recommended profile, warn and continue if the arithmetic candidate is feasible. Only the arithmetic engine may refuse because no candidate fits.

## Implementation notes for lib/tune.sh

The eventual common function should accept RAM, swap, cores, requested profile, workload, server role, and explicit local service-cost inputs. It must not hardcode MariaDB base memory. A slave_web role normally supplies zero local MariaDB cost; externally hosted Redis supplies zero local Redis cost. Local worker memory remains a cost even when the worker connects to an external database.

Two functional corrections are mandatory:

1. **Lean-search tie-break:** maximize child count, then maximize buffer size at the winning child count. The former condition updated the buffer only when child count increased and therefore retained the smallest buffer among tied winning child counts. The exact selection rule belongs in docs/TUNING.md and must be covered by tests.
2. **Worker DB connections:** include worker_db_connections in the derived MariaDB connection budget as specified in docs/TUNING.md. X-Cart defaults to four worker DB connections pending measurement at M2b; other listed workloads default to zero. This prevents a supervised queue worker's persistent connections from being omitted.

The arithmetic must distinguish infeasible candidates from advisory policy floors. Redis maxmemory remains a configured cost, never a search variable.

## Milestone placement

- M2a extension: workload registry and X-Cart inputs; advisory memory/profile warnings.
- M2b: measure assumptions and verify arithmetic, including worker DB connection behavior.
- No implementation or test result is claimed by this design document.
