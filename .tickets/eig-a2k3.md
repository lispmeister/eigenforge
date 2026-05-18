---
id: eig-a2k3
status: closed
deps: []
links: []
created: 2026-05-14T07:44:33Z
type: task
priority: 3
assignee: lispmeister
---
# Add the V2 forward-compat trace fixture and verifier warning

§13 already defines the V2-shape forward-compat fixture and the V1 verifier behavior: accept `consensus_status=quorum_finalized` with a logged warning. The remaining work is to create the fixture and make `mix eigenforge.ledger.verify` emit the documented warning instead of treating the shape as a spec question.

Add `test/golden_traces/v2_quorum_shape_compat.json` containing a hand-built `command_envelope_issued` ledger event with `consensus_status=quorum_finalized`, non-empty `quorum_ref`, and supporting vote references. Implement the corresponding verifier behavior.

## Acceptance Criteria

`test/golden_traces/v2_quorum_shape_compat.json` is committed. `mix eigenforge.ledger.verify` has the documented V1 warning behavior on the fixture. §13 and the verifier agree on the forward-compat rule.


## Notes

**2026-05-14T07:57:04Z**

Spec updated: §13 V2-Shape Forward-Compat section describes the fixture and V1 verifier behavior (accept with warning). §11 verifier step 6 updated. The fixture file test/golden_traces/v2_quorum_shape_compat.json still needs to be created and the verifier warning implemented.
