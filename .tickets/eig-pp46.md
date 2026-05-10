---
id: eig-pp46
status: closed
deps: [eig-60h5, eig-p9ms]
links: []
created: 2026-05-08T13:33:14Z
type: feature
priority: 1
assignee: lispmeister
tags: [next-slice]
---
# Add local SQLite append-only ledger_events table

Spec §11: each core node owns a local SQLite command ledger. Implement a node-local `ledger_events` table with unique local `sequence`, `event_id`, and `event_hash`; required `core_node_id`, `previous_event_hash`, `payload_hash`, and `signature`; decision-chain events require `consensus_decision_id` and `consensus_status`, while non-decision events may store null consensus fields and V1 `quorum_ref={}`. Enforce the sequence-1 `ledger_genesis` constraint. Ledger writes must be plain inserts only. Runtime code must not use UPDATE, DELETE, INSERT OR REPLACE, ON CONFLICT DO UPDATE, table rebuild/swap flows, resequencing, backfilling, or catch-up paths that rewrite existing ledger rows.

## Acceptance Criteria

Local SQLite initialization succeeds for a configured `EIGENFORGE_CORE_NODE_ID` and `EIGENFORGE_CORE_DB_PATH`; WAL mode is enabled; `UPDATE` and `DELETE` rejection triggers protect `ledger_events`; uniqueness and genesis constraints are enforced; projection tables are separate mutable read models and can be rebuilt without modifying ledger rows.

## Notes

**2026-05-09T14:00:19Z**

Aligned with revised spec: ticket now targets local SQLite append-only ledger_events per core node instead of Ecto/Postgres; acceptance forbids update/delete/replace/resequence/backfill write paths and keeps projections separate.

**2026-05-10T05:09:18Z**

2026-05-10 spec clarification update: ledger schema must use fixed V1 event_type values, keep SQLite UPDATE/DELETE rejection triggers in V1, and allow consensus_decision_id/consensus_status to be null for non-decision events while requiring quorum_ref={} in V1.
