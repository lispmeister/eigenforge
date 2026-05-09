---
id: eig-n1ik
status: open
deps: []
links: []
created: 2026-05-08T13:32:45Z
type: chore
priority: 2
assignee: lispmeister
tags: [code-quality]
---
# Stringify ledger event payload keys consistently

trace.ex:319-320 stores Map.from_struct(payload) with atom keys. After a JSON round-trip the same map has string keys. Makes pattern matching inconsistent between in-memory and loaded traces.

## Acceptance Criteria

In-memory event.payload and JSON-round-tripped event.payload are structurally equal; string keys used throughout.

