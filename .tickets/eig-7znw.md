---
id: eig-7znw
status: open
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

