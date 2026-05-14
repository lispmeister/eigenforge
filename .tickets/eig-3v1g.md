---
id: eig-3v1g
status: closed
deps: []
links: []
created: 2026-05-14T04:44:06Z
type: chore
priority: 3
assignee: lispmeister
---
# Return query-specific errors from LedgerSQLite

LedgerSQLite.query_json/2 rescues all exceptions as {:sqlite_init_failed, ...} even though it is performing query work. That makes operational diagnosis ambiguous and mixes init and query failure categories.

## Acceptance Criteria

Query failures return a query-specific error tuple or preserve the original category; init failures remain distinct; tests cover at least one failing query path and assert the error shape is specific to query work.

