---
id: eig-nkgh
status: closed
deps: []
links: []
created: 2026-05-14T04:44:06Z
type: bug
priority: 2
assignee: lispmeister
---
# Fix after-action stale-evidence ordering check

AfterActionObserver.accepted_monotonic_ms/1 tries to read metadata from %CommandEnvelope{}, but the generated envelope has no metadata field. That makes the monotonic fallback path dead and weakens stale confirmation filtering.

## Acceptance Criteria

The stale-evidence check uses fields that actually exist on the command envelope or a supported external evidence structure; the dead metadata lookup is removed; tests cover the monotonic ordering case and the command-envelope path compiles cleanly without the current warning.

