---
id: eig-hyel
status: closed
deps: []
links: []
created: 2026-05-18T12:48:27Z
type: task
priority: 2
assignee: lispmeister
---
# Add integrity verification to IO command execution store

The IO command execution store should not only validate JSON shape/version. It needs a signed manifest or HMAC-based integrity check so corruption or tampering is detectable on startup and restart.

## Acceptance Criteria

Command execution store startup rejects tampered or unverifiable contents, not just malformed JSON; duplicate-idempotency restart coverage still passes; the store records how integrity is verified.

