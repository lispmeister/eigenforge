---
id: eig-rsut
status: open
deps: [eig-ibj4]
links: []
created: 2026-05-14T05:54:26Z
type: bug
priority: 2
assignee: lispmeister
---
# Make ledger append and projection update atomic in a single SQLite transaction

LedgerWriter.append_once/2 makes three separate connection-per-call round-trips: LedgerSQLite.tail, LedgerSQLite.append_event, LedgerProjections.apply_event. Each opens and closes its own SQLite connection. A crash after the INSERT but before apply_event completes leaves the ledger and projections diverged until the next startup rebuild. Spec §11 requires a single transaction: begin, read tail, insert event, update projections, commit. Fixing this requires a persistent shared connection (eig-ibj4) so a transaction can be held open across all steps.

## Acceptance Criteria

LedgerWriter.append_once/2 executes tail read, ledger INSERT, and projection UPSERT inside a single SQLite BEGIN IMMEDIATE ... COMMIT transaction on one persistent connection. A simulated crash after INSERT (test using a mock or fault injection) leaves the ledger and projection consistent after restart. All existing ledger tests pass.

