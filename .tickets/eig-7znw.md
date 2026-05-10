---
id: eig-7znw
status: closed
deps: []
links: []
created: 2026-05-08T13:32:45Z
type: chore
priority: 2
assignee: lispmeister
tags: [code-quality]
---
# Add reasoner_outcome_id field to ReasonerOutcome contract

ReasonerOutcome struct is missing reasoner_outcome_id. policy_decision/5 in Trace re-derives it with a separate stable_id call (trace.ex:218), risking silent drift.

## Acceptance Criteria

Policy decision references the reasoner outcome's own ID field; golden traces regenerated.


## Notes

**2026-05-10T05:10:08Z**

2026-05-10 spec clarification update: reasoner_outcome_id is now an explicit V1 ReasonerOutcome contract field and must be generated from schema, not re-derived by policy code.

**2026-05-10T06:03:32Z**

Added reasoner_outcome_id to reasoner_outcome.schema.json and regenerated the ReasonerOutcome contract. Trace outcomes now set their own reasoner_outcome_id, and policy decisions reference reasoner.reasoner_outcome_id instead of re-deriving it. Regenerated committed golden traces because signed payloads and ledger hashes changed. Verified mix test, mix compile --warnings-as-errors, mix run tools/smoke_contracts.exs, git diff --check, and tk dep cycle.
