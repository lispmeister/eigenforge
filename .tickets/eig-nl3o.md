---
id: eig-nl3o
status: closed
deps: []
links: []
created: 2026-05-14T05:01:56Z
type: bug
priority: 2
assignee: lispmeister
---
# Fix AfterActionObserver.observe/1 to distinguish confirmed_changed vs confirmed_already_in_state

AfterActionObserver.observe/1 always emits status: 'confirmed_changed' regardless of pre-command fan state. The spec (§10) requires confirmed_already_in_state when the pre-command state already matched the requested state. A simulator fixture with fan_state=on requesting on will incorrectly record confirmed_changed.

## Acceptance Criteria

- observe/1 accepts a pre_command_snapshot argument (or observe/2 is added)
- returns confirmed_already_in_state when pre_command fan_state matches requested_state
- returns confirmed_changed otherwise
- existing trace tests updated to pass pre_command_snapshot
- golden trace acceptance test case 2 (fan already on) records confirmed_already_in_state

