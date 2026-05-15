---
id: eig-dfz1
status: open
deps: [eig-49a5]
links: []
created: 2026-05-15T13:29:32Z
type: task
priority: 3
assignee: lispmeister
---
# Implement IO quorum judge for signed proposals

Teach eigenforge_io to collect signed proposals from core nodes, verify proposal signatures, enforce the 2-of-3 rule, and execute the actuator at most once when quorum is reached. This is the V2 IO-as-judge path described in PROTOTYPE-V1-SPEC.md.

## Acceptance Criteria

IO verifies signed proposals, rejects invalid or duplicate proposals, refuses action when fewer than two valid proposals arrive, and executes at most once when quorum is reached. IO publishes quorum evidence with the after-action publication. Tests cover allow, deny, duplicate, and quorum paths.

