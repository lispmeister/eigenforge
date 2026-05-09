---
id: eig-qkkk
status: closed
deps: []
links: []
created: 2026-05-09T13:48:10Z
type: task
priority: 1
assignee: lispmeister
---
# Align slice-one code with local SQLite spec

Update existing slice-one trace/contracts implementation to match revised local SQLite per-core persistence and finalization model.

## Acceptance Criteria

Ledger events include core_node_id and consensus fields; trace output reflects finalized local commits before command delivery; schemas/generated modules/tests/golden traces are aligned; verification covers consensus status/reference shape.


## Notes

**2026-05-09T13:51:54Z**

Aligned slice-one trace/contracts code with revised local SQLite spec: LedgerEvent schema/generated contract now includes core_node_id, consensus_decision_id, consensus_status, and quorum_ref; trace runner emits local_sqlite/single_core_finalized metadata and commit steps; verifier/tests/goldens assert local commit before delivery.
