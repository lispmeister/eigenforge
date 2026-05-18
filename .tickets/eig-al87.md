---
id: eig-al87
status: closed
deps: []
links: []
created: 2026-05-18T12:48:27Z
type: task
priority: 2
assignee: lispmeister
---
# Add OODA and TRACE coverage metadata to trace output

Trace JSON should include stable OODA step IDs and explicit coverage links for TRACE-V1 acceptance cases so verify_file can validate required coverage instead of only comparing generic step names.

## Acceptance Criteria

Trace JSON includes OODA-V1-* step identifiers and trace coverage metadata; trace verification checks coverage for committed golden traces; the first three simulator traces still pass.

