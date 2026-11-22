-- Copyright (c) 2026 Lewis James Seals Jr.
-- SPDX-License-Identifier: MIT
-- Author: Lewis James Seals Jr.
-- Repository: https://github.com/ljrseals-dev/StackAlign
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL, description TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS tasks(
 id TEXT PRIMARY KEY CHECK(length(id)=36),
 task_type TEXT NOT NULL CHECK(task_type IN ('health_check','website_deploy','database_backup','website_migration')),
 description TEXT NOT NULL CHECK(length(description) BETWEEN 1 AND 500),
 status TEXT NOT NULL CHECK(status IN ('pending','running','succeeded','failed')),
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tasks_status_created ON tasks(status,created_at);
CREATE TABLE IF NOT EXISTS task_events(
 event_id INTEGER PRIMARY KEY AUTOINCREMENT,
 task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
 event_type TEXT NOT NULL CHECK(event_type IN ('created','running','succeeded','failed')),
 detail TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_task_events_task_time ON task_events(task_id,created_at);
INSERT OR IGNORE INTO schema_migrations VALUES(1,strftime('%Y-%m-%dT%H:%M:%fZ','now'),'Initial local state and task lifecycle');
COMMIT;
