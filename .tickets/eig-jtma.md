---
id: eig-jtma
status: closed
deps: [eig-777e]
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


## Notes

**2026-05-10T05:09:48Z**

2026-05-10 spec clarification update: expiry math should use canonical millisecond UTC timestamps and deterministic trace clocks; expires_at remains derived from issued_at plus configured TTL.
