# StackAlign Local State Database and Task Lifecycle

## Purpose

StackAlign now has a local deterministic state store for its own operational records. It is separate from MariaDB databases provisioned for hosted applications. SQLite is the initial backend because a single-host controller does not need another network service. No LLM, network connection, telemetry, or remote configuration is involved.

## Initialize

Install the distribution SQLite CLI package (typically sqlite on EL-family distributions and sqlite3 on Debian/Ubuntu), then:

```bash
sudo install -d -o root -g root -m 0700 /var/lib/stackalign
sudo bash bin/stackalign state init --apply
sudo bash bin/stackalign state status
```

The default database is /var/lib/stackalign/state.db. Tests and isolated installs may override SA_STATE_DB with an absolute path whose parent already exists and is not a symlink. Every resolved directory component must be owned by root or the invoking user and must not be group/other-writable; the root-owned sticky /tmp directory is permitted for private per-user child directories. The database is created with mode 0600. Existing files must be regular, non-symlink files owned by the invoking user and mode 0600 or 0400. The parent directory is intentionally not created implicitly.

## Task lifecycle

Registered task types: health_check, website_deploy, database_backup, website_migration. Registration does not mean the underlying hosting operation is implemented. This milestone stores task intent and enforces transitions; it does not execute arbitrary shell commands or claim to deploy websites.

```bash
stackalign state task create health_check "Inspect web and database services" --apply
stackalign state task list
stackalign state task start <task-id> --apply
stackalign state task complete <task-id> "Checks passed" --apply
stackalign state task fail <task-id> "Nginx configuration test failed" --apply
```

Valid transitions are pending -> running -> succeeded/failed. Invalid transitions are rejected atomically. Accepted transitions are recorded in task_events. Task descriptions are plain text; never put secrets in them.

## Schema evolution and recovery

The initial SQL migration is versioned and idempotent, runs in a transaction, and records schema version 1. Future migrations must be additive/versioned and must not edit an already-released migration in place. Back up the database only while StackAlign is quiescent, or use a SQLite online-backup mechanism in a future dedicated workflow. Task history is not a backup.

## Limits

- Single-host state only; no distributed coordination.
- Task lifecycle tracking only; no generic command runner, scheduler, retries, or rollback engine.
- Task type allowlisting is not proof that each task implementation exists.
- SQLite CLI availability and real EL9 permissions still need deployment validation.
- An optional LLM may later translate natural language into a proposed allowlisted task. The deterministic engine remains authoritative.
