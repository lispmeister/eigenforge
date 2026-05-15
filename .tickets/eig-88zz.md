---
id: eig-88zz
status: closed
deps: []
links: []
created: 2026-05-14T05:55:08Z
type: task
priority: 2
assignee: lispmeister
---
# Define the stale_snapshot_denied payload contract

This is still an open spec/design decision. V1 currently uses a `PolicyDecision` payload for `stale_snapshot_denied`, reusing the same struct as `policy_decision_recorded`, but the spec does not yet say that explicitly. A future implementation could reasonably choose a different payload shape unless the contract is pinned down.

## Acceptance Criteria

PROTOTYPE-V1-SPEC.md §11 explicitly states the payload type and required fields for `stale_snapshot_denied` events, and the corresponding JSON schema exists or is explicitly noted as shared with `policy_decision`. The implementation and schema agree with the spec.

## Notes

**2026-05-15T13:26:36Z**

Resolved by PROTOTYPE-V1-SPEC.md update: stale_snapshot_denied now explicitly uses the PolicyDecision payload contract shared with policy_decision_recorded.
