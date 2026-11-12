# Changelog

## Unreleased

### Documentation

- Corrected project status to distinguish repository design documents from implementation; conversation-only drafts are not repository files or test results.
- Reconciled the docs with the bootstrap code already present on main: the configuration parser, CLI/support libraries, provisional tuner, and five provisional tuner tests exist, but the frozen M2a contract and full installer behavior remain unimplemented.
- Explicitly recorded that the provisional tuner is lean-only, uses a 32 MiB child assumption, refuses standard, and is not wired to the CLI tune command.
- Retracted the hand-computed sizing table and required future tables to be generated from the implemented tuner using a checked script.
- Clarified that memory/profile policy floors are advisory and arithmetic infeasibility is the only hard sizing refusal.
- Made local service costs explicit tuner inputs; a web-only slave_web role does not reserve local MariaDB or externally hosted Redis.
- Added workload registry notes for the lean-search buffer tie-break and worker database connection budgeting.
- Added the slave-web isolation design with explicit PHP-level versus kernel enforcement boundaries, two-live-tenant M2b verification, and M7 kernel-test gates.
- Added the configuration schema proposal for server roles, tenants, and Redis services.

See the pull request description for the correction rationale and review checklist.
