---
id: eig-vte2
status: closed
deps: []
links: []
created: 2026-05-18T12:48:27Z
type: task
priority: 2
assignee: lispmeister
---
# Add invariant IDs to ledger and trace verification failures

LedgerTooling and trace verification should cite stable invariant IDs in errors and warnings. This should cover hash chain, signature, sequence, consensus, and trace-coverage failures.

## Acceptance Criteria

mix eigenforge.ledger.verify and mix eigenforge.trace.verify report failure messages that include INV-01 through INV-14 where applicable; errors remain deterministic and still identify the first failing condition.

