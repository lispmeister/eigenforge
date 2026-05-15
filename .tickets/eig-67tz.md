---
id: eig-67tz
status: open
deps: [eig-8okp]
links: []
created: 2026-05-15T13:30:31Z
type: task
priority: 3
assignee: lispmeister
parent: eig-dfz1
---
# Implement IO quorum aggregation and execution

Teach eigenforge_io to collect signed proposals, verify signatures, enforce the 2-of-3 voting rule, and execute the actuator at most once when quorum is reached. This is the core of the V2 IO-as-judge boundary.

## Acceptance Criteria

IO verifies signed proposals, rejects invalid or duplicate proposals, refuses action when fewer than two valid proposals arrive, and executes at most once when quorum is reached. Tests cover allow, deny, duplicate, and quorum paths.

