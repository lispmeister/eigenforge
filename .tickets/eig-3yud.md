---
id: eig-3yud
status: open
deps: [eig-dfz1]
links: []
created: 2026-05-15T13:29:32Z
type: task
priority: 3
assignee: lispmeister
---
# Persist quorum_finalized ledger events with supporting votes

After IO publishes a quorum-finalized after-action event, each participating core node must append a local quorum_finalized ledger event that references the finalized decision and supporting vote evidence. This preserves the append-only local ledger model for V2.

## Acceptance Criteria

Participating cores persist quorum_finalized events only after observing IO's quorum-finalized after-action publication. The persisted event includes the finalized decision and supporting vote references required by the spec. Verification and restart recovery cover the quorum evidence shape.

