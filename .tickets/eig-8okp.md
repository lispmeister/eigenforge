---
id: eig-8okp
status: open
deps: []
links: []
created: 2026-05-15T13:30:31Z
type: task
priority: 3
assignee: lispmeister
parent: eig-dfz1
---
# Add signed_proposal delivery path to IO

Implement the path that gets signed_proposal messages from core nodes to eigenforge_io for V2 IO-as-judge mode. The exact transport should fit the existing mailbox boundary and spec constraints, but the key requirement is that IO receives signed proposals with the metadata needed for quorum evaluation.

## Acceptance Criteria

IO can receive signed_proposal messages from core nodes. The delivery path preserves proposal identity and signature data. Existing V1 command-envelope delivery remains unchanged.

