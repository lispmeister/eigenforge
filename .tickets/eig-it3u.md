---
id: eig-it3u
status: closed
deps: []
links: []
created: 2026-05-14T05:01:48Z
type: task
priority: 1
assignee: lispmeister
---
# Replace System.cmd sqlite3 CLI with exqlite in LedgerSQLite

LedgerSQLite shells out to the sqlite3 binary via System.cmd for all reads and writes. This bypasses Elixir's connection lifecycle, prevents parameterized queries, and makes the three-retry ledger persistence rule (spec §9) impossible to enforce atomically inside a single transaction. Replace with exqlite (or ecto_sqlite3) so that append_event/2 and query helpers use a supervised connection, prepared statements, and can wrap the genesis-check + insert + projection-update in a single SQLite transaction.

## Acceptance Criteria

- append_event/2 uses parameterized inserts, not string interpolation
- init/2 opens a supervised exqlite connection in WAL mode
- three-retry rule from spec §9 is implementable inside a DB transaction
- no System.cmd('sqlite3', ...) calls remain in LedgerSQLite
- existing ledger tests pass

