---
id: eig-perg
status: open
deps: [eig-67tz]
links: []
created: 2026-05-15T13:30:32Z
type: task
priority: 3
assignee: lispmeister
parent: eig-dfz1
---
# Publish quorum evidence and IO fault/status for proposal outcomes

After quorum evaluation, IO must publish the quorum evidence attached to the after-action result and emit the correct IO fault/status stream entries for invalid, duplicate, or insufficient proposal cases. This keeps operators and core informed without turning the proposal path into authority.

## Acceptance Criteria

Quorum-finalized after-action publications carry the required quorum evidence. Invalid, duplicate, and insufficient-proposal cases publish the expected IO fault/status events. Tests cover the published fault/status shapes and the quorum-evidence output.

