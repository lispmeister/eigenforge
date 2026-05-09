---
id: eig-jtma
status: open
deps: []
links: []
created: 2026-05-08T13:32:45Z
type: chore
priority: 2
assignee: lispmeister
tags: [code-quality]
---
# Compute expires_at from issued_at in command envelope

lib/eigenforge/trace.ex:248-251 hardcodes expires_at as a literal date string instead of issued_at + 5 seconds.

## Acceptance Criteria

Changing the trace timestamp does not break envelope expiry math; expires_at is always issued_at + configured TTL.

