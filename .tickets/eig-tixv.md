---
id: eig-tixv
status: closed
deps: []
links: []
created: 2026-05-14T05:54:19Z
type: task
priority: 2
assignee: lispmeister
---
# Parameterize LedgerProjections SQL

LedgerProjections builds all SQL via sql_string/1, sql_nullable/1 helpers and inline String.replace escaping (ledger_projections.ex:202-260, snapshot_subscriber.ex:178-186, 484-490). LedgerSQLite was rewritten to use exqlite parameterized bind params in eig-it3u, but LedgerProjections was not updated. The manual escaping is not wrong for the current inputs (all internally generated), but it is inconsistent with the rest of the codebase and contrary to the spirit of the eig-it3u migration.

## Acceptance Criteria

All SQL in LedgerProjections and SnapshotSubscriber uses exqlite prepare/bind params instead of string interpolation. The sql_string/1 and sql_nullable/1 private helpers in LedgerProjections are removed. All existing ledger and pipeline tests pass.
