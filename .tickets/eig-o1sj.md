---
id: eig-o1sj
status: closed
deps: [eig-pp46, eig-5u7f]
links: []
created: 2026-05-08T13:33:14Z
type: feature
priority: 1
assignee: lispmeister
tags: [next-slice]
---
# Wire local SQLite ledger writer process

Spec §11: one writer process per core node opens an immediate SQLite write transaction, reads the local ledger tail, computes the next local sequence, previous hash, payload hash, event hash, and signature, inserts the event, updates separate projection tables, and commits. No update/delete/replace/resequence/backfill path may touch `ledger_events`. Three-attempt retry; returns `{:error, :ledger_persistence_failed}` per spec §9.

## Acceptance Criteria

Concurrent append requests serialize through one node-local writer; failed local SQLite commits return the documented tuple; no command is delivered before a finalized local ledger commit; tests prove no `INSERT OR REPLACE`, `ON CONFLICT DO UPDATE`, `UPDATE`, or `DELETE` path exists for ledger rows.

## Notes

**2026-05-09T14:00:19Z**

Aligned with revised spec: ticket now targets one node-local SQLite writer using immediate transactions and plain inserts, not Postgres advisory locks; command delivery waits for finalized local commit.

**2026-05-10T05:09:18Z**

2026-05-10 spec clarification update: writer must support the clarified event cardinality paths and command_envelope_issued decision event references, while keeping one writer, plain inserts, WAL, three retry attempts, and no command delivery before commit.
