---
id: eig-bcyj
status: open
deps: [eig-3yud]
links: []
created: 2026-05-15T13:29:32Z
type: task
priority: 3
assignee: lispmeister
---
# Add quorum catch-up and split-brain repair

Implement the V2 catch-up path for lagging core nodes: append local catch-up evidence for finalized decisions, avoid copying foreign ledger rows, and reject conflicting finalized decisions or duplicate idempotency keys during repair. This is the network-partition side of the IO-as-judge design.

## Acceptance Criteria

Lagging nodes append local catch-up evidence only. Foreign ledger rows are never copied into the local chain. Conflicting finalized decisions or duplicate idempotency keys fail verification. Healing restores proposal submission only after catch-up evidence is verified.

