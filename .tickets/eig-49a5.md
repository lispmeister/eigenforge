---
id: eig-49a5
status: open
deps: []
links: []
created: 2026-05-15T13:29:32Z
type: task
priority: 3
assignee: lispmeister
---
# Implement signed_proposal contract and core emission

Add the V2 signed_proposal contract and the core-side emission path for IO-as-judge mode. V2 cores should emit signed proposals instead of command envelopes, carrying the normalized action/no-action, idempotency_key, proposal identity, and vote signature data needed by IO.

## Acceptance Criteria

Signed_proposal contract exists in eigenforge_contracts. Core can emit signed proposals with the fields needed for IO quorum processing. V1 command-envelope flow remains unchanged. Tests cover schema validation and proposal emission.

