---
id: eig-n1ik
status: closed
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


## Notes

**2026-05-10T05:10:08Z**

2026-05-10 spec clarification update: payload key stringification must preserve canonical JSON key sorting and schema field names exactly, since schema/prose drift is now treated as a V1 contract failure.
