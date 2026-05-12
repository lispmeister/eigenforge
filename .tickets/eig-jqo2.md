---
id: eig-jqo2
status: closed
deps: []
links: []
created: 2026-05-12T09:11:23Z
type: bug
priority: 1
assignee: lispmeister
tags: [v1, spec, tests, io, restart]
---
# Add IO restart test for persisted duplicate idempotency key

Spec fault-injection list calls for IO restart with persisted duplicate idempotency_key. Current coverage verifies duplicates in-process but not across IO process restart with persisted command execution store state.

## Acceptance Criteria

1. Add a test that executes a command, restarts HomeAssistantClient with same command execution store, and replays same command idempotency_key. 2. Assert second execution is rejected as duplicate and no second transport call occurs. 3. Assert receipt phase behavior is preserved (no io_accepted transition for duplicate replay). 4. Full mix test passes.

