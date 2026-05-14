---
id: eig-om8t
status: closed
deps: []
links: []
created: 2026-05-14T07:45:09Z
type: chore
priority: 4
assignee: lispmeister
---
# Spec §4: document wall-clock skew recovery footgun explicitly

§4 specifies the conservative no-new-command path when wall-clock evidence is missing or appears to move backward. The implicit consequence — a single clock skew at restart can mark physically-successful pending commands timed_out — should be stated explicitly so operators know.

Proposed spec change: add one paragraph to §4 naming the failure mode. Recommend either (a) operator practice of not restarting during known clock changes, or (b) a future clock_skew_observed ledger event that gates terminal recovery before producing timed_out after-actions. No code change in V1.

## Acceptance Criteria

§4 has an explicit paragraph naming the wall-clock skew consequence and providing a recommended operator practice or future mitigation path.

