---
id: eig-uaas
status: closed
deps: []
links: []
created: 2026-05-18T12:48:27Z
type: bug
priority: 2
assignee: lispmeister
---
# Remove bare command execution path from IO command executor

CommandExecutor exposes a bare execute/2 path that dispatches without a verified delivery receipt. Physical execution should require the command plus receipt shape, or the bare path should be private/test-only.

## Acceptance Criteria

IO physical command execution requires verified delivery-envelope input; the public execution surface does not dispatch bare commands without receipt verification; existing tests still cover verified delivery and stub targets.

