---
id: eig-a2k3
status: open
deps: []
links: []
created: 2026-05-14T07:44:33Z
type: task
priority: 3
assignee: lispmeister
---
# Add V2-shape forward-compat golden trace fixture to verify migration promise

§11 and §2 promise that V1 field shapes (consensus_decision_id, consensus_status, quorum_ref, supporting vote refs) leave V2 migration straightforward. Today this is only asserted in field declarations. No fixture exercises a quorum-shaped ledger event being read by V1 tooling. A single forward-compat fixture converts the promise into a verified property.

Proposed change: add test/golden_traces/v2_quorum_shape_compat.json containing a hand-built command_envelope_issued ledger event with consensus_status=quorum_finalized, non-empty quorum_ref, and supporting vote references. Determine and pin in §11 whether mix eigenforge.ledger.verify should (a) accept the shape with a known V1 warning, or (b) reject it with a known unsupported_consensus_status error. Implement the corresponding behavior.

## Acceptance Criteria

test/golden_traces/v2_quorum_shape_compat.json committed. mix eigenforge.ledger.verify has a deterministic, documented outcome on it (accept-with-warning or reject-with-known-error). §11 explicitly states the V1 behavior on quorum-shaped events.


## Notes

**2026-05-14T07:57:04Z**

Spec updated: §13 V2-Shape Forward-Compat section describes the fixture and V1 verifier behavior (accept with warning). §11 verifier step 6 updated. The fixture file test/golden_traces/v2_quorum_shape_compat.json still needs to be created and the verifier warning implemented.
