---
id: eig-ibj4
status: open
deps: []
links: []
created: 2026-05-14T05:37:29Z
type: task
priority: 2
assignee: lispmeister
---
# Use a supervised persistent SQLite connection

LedgerSQLite currently opens and closes an Exqlite.Sqlite3 connection for every append_event/2, query/2, and query_json/2 call. Each open is a file-system round trip and acquires the WAL reader/writer lock fresh. This is correct for correctness but unnecessary overhead under any sustained write rate, and it makes WAL checkpoint behavior less predictable. The db_connection dependency (already present via exqlite 0.36.0) provides a pooling abstraction that could hold a single supervised connection per db_path without changing the public LedgerSQLite API.

## Acceptance Criteria

- LedgerSQLite holds a supervised connection (GenServer or db_connection pool of size 1) opened once at init time
- append_event/2, query/2, and query_json/2 use the persistent connection rather than open/close per call
- WAL mode and foreign-keys PRAGMA are set once on connection open, not per call
- The public API signatures (db_path, sql/event args) remain unchanged so all callers compile without modification
- All existing ledger tests pass
- No System.cmd calls introduced
