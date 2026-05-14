---
id: eig-88zz
status: open
deps: []
links: []
created: 2026-05-14T05:55:08Z
type: task
priority: 2
assignee: lispmeister
---
# Spec §11: specify the required payload shape for stale_snapshot_denied ledger events

Spec §11 defines required payload fields for every V1 event type except stale_snapshot_denied. The implementation uses a PolicyDecision struct as the payload (reusing the same struct from the policy_decision_recorded event emitted immediately before). A future implementation could reasonably make a different choice with no spec to arbitrate. The spec should either (a) state that the payload is a PolicyDecision with the same fields as policy_decision_recorded, or (b) define a separate stale_snapshot_denied payload contract.

## Acceptance Criteria

PROTOTYPE-V1-SPEC.md §11 explicitly states the payload type and required fields for stale_snapshot_denied events. The corresponding JSON schema in priv/schemas exists or is explicitly noted as shared with policy_decision. The implementation and schema agree with the spec.

