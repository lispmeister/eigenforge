---
id: eig-tx3w
status: closed
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 1
assignee: lispmeister
---
# Make ledger append and projection update transactional (§11)

The spec (§11) requires:

> "The local SQLite ledger insert path should run in a transaction that:
> 1. Begins an immediate write transaction.
> 2. Reads the latest `event_hash`.
> 3. Assigns the next `sequence`.
> 4. Computes `previous_event_hash`, `payload_hash`, and `event_hash`.
> 5. Inserts the event.
> 6. Updates separate projection tables derived from the inserted event.
> 7. Commits."

Currently `LedgerWriter.append_once` (`ledger_writer.ex:123–133`) opens three separate SQLite connections — `LedgerSQLite.tail()`, `LedgerSQLite.append_event()`, `LedgerProjections.apply_event()`. A crash between steps 5 and 6 leaves the ledger event committed but the projection stale. Projections rebuild at startup (`LedgerWriter.init` calls `LedgerProjections.rebuild`), but this is recoverable inconsistency, not the transactional guarantee the spec requires.

Required changes:
1. Refactor `LedgerSQLite` to expose a transaction-aware API: open one connection, begin `IMMEDIATE`, perform tail read + insert, update projections, commit — all within one connection and transaction.
2. Alternatively, use a single `exqlite` connection held open by `LedgerWriter` (matching "one writer process per core node") and issue `BEGIN IMMEDIATE … COMMIT` across the tail read, insert, and projection update in one transaction.
3. Update `LedgerProjections` SQL helpers to work within a provided connection.
4. Ensure `LedgerSQLite.init/2` runs in WAL mode before the first transaction (`PRAGMA journal_mode=WAL`).
5. Existing tests should still pass; add a test asserting that a simulated crash after insert but before projection update triggers a clean rebuild at next startup.

## Acceptance Criteria

- Tail read, ledger insert, and projection update execute within a single `BEGIN IMMEDIATE … COMMIT` transaction.
- `mix test` green.
- `mix eigenforge.ledger.verify` still passes on a ledger written by the new path.
