# Workload tuning contract

**Status: design only; implementation pending.** The repository does not yet contain lib/tune.sh, lib/config.sh, or tests/test_tune_math.py. Values below are design inputs and assumptions, not measured results or executable behavior.

## One engine, workload data

There is one tuning calculation and one one-dimensional candidate search. Workloads supply data to that engine; they do not select separate algorithms. The server role and locally hosted services also supply cost inputs. The calculation must not hardcode a MariaDB reservation.

The workload registry is specified in [research/workload-registry.md](research/workload-registry.md). It includes child_rss_mib, worker_memory_mib, redis_sessions_mib, redis_cache_mib, policy advisory fields, and worker_db_connections.

## Arithmetic and refusal semantics

Inputs include RAM, swap, CPU count, requested profile, workload, server role, and local service costs. The specified usable-memory calculation is:

- usable_mib = ram_mib + min(swap_mib * 0.5, ram_mib * 0.25)
- ceiling_mib = floor(usable_mib * 0.90)

The prior illustrative local-service decomposition was OS 200 + MariaDB base 120 + PHP master 15 + Nginx 10 + OPcache 32 + safety margin 140 + X-Cart worker 128 + Redis sessions 32 + Redis cache 64 = **741 MiB**. The 120 MiB MariaDB and 32/64 MiB Redis terms apply only when those services are local and configured at those values. The fixed reserve is the sum of supplied local fixed costs: OS, locally hosted MariaDB base, PHP master, Nginx, OPcache, safety margin, workload worker memory, and locally hosted Redis session/cache memory. The engine consumes these as inputs; it does not assume every service is local. For example, slave_web normally supplies zero local MariaDB cost, and externally hosted Redis contributes zero local Redis memory cost. If Redis is local, its configured memory is a cost, not a search variable.

For the standard profile, the current design allocates 40% of memory remaining after the reserve to PHP workers; the remainder is database-available budget. Candidate max_children is the integer PHP budget divided by the workload child RSS assumption. The buffer-pool target is 60% of database-available memory, bounded by the documented minimum and by leaving required non-buffer-pool database headroom. Exact integer rounding and boundary handling must be implemented once and tested before any generated table is published.

For the lean profile, search child counts {1, 2, 3, 4} and buffer sizes {32, 48, 64} MiB. Select the feasible candidate with the greatest child count; when child counts tie, select the largest buffer. The implementation must use the comparison equivalent to:

    if (( total <= ceiling && (c > best_c || (c == best_c && b > best_b)) )); then
      best_c="$c"; best_b="$b"
    fi

This corrects the previous defect where buffer size was only updated when child count increased, causing the smallest buffer to win among equally optimal child counts.

**Hard refusal:** only arithmetic infeasibility—no candidate satisfies memory constraints—may refuse sizing. A request below a workload min_ram_mib policy floor, or for a profile below the workload preferred min_profile, produces an explicit warning and a prominent doctor finding, but does not itself refuse an otherwise feasible calculation. Requested profile and policy warnings must remain visible in plan output.

## Database connections

The derived connection budget must include background-worker demand:

    max_connections = max_children * 2 + worker_db_connections + 5

worker_db_connections is workload-registry data: zero for plain PHP, WordPress, and Laravel; default four for X-Cart pending measurement at M2b. This value is an assumption until measured. It must not be omitted from the MariaDB connection budget.

Redis maxmemory is configured capacity, not a tuner search dimension. Explicit user configuration overrides workload defaults. The local Redis memory cost supplied to the tuner must reflect effective configured values only when Redis is hosted on this node.

## Measurement and publication gate

All child RSS values, worker costs, fixed service costs, and worker connection counts are assumptions until measured in the specified M2b environments. Do not describe them as measured or validated.

The previously discussed worked sizing table is **retracted**. It used a reserve of 756 MiB even though the listed components sum to 741 MiB, and its reported child counts did not follow the stated standard formula. Do not replace it with another hand-computed table.

**Rule:** every sizing table must be produced by running the actual implemented function against a checked script or test harness; paste the actual command and output into the review record and this document. If the function does not yet exist, publish no worked sizing table. The arithmetic script and tests must be committed with the implementation, not represented as conversation-only artifacts.

## Role-aware service-cost inputs

The same formula serves all node roles. The role determines which services are local and therefore which fixed-cost inputs are nonzero. A web-only slave_web node does not reserve local MariaDB memory by default. If MariaDB or Redis is external, the corresponding local service cost is zero. A locally supervised application worker still contributes worker memory and worker database connection demand even when the database is remote.

See [the slave-web role design](research/slave-web-node.md) and [the workload registry](research/workload-registry.md).
