---
id: eig-962v
status: closed
deps: []
links: []
created: 2026-05-12T08:24:27Z
type: bug
priority: 1
assignee: lispmeister
tags: [core, after-action, io]
---
# Fix after-action confirmation ordering to use IO-local receive evidence

The current after-action path compares confirmation evidence against snapshot_seq derived from the pre-command snapshot, which is a proxy for source order rather than delivery-local receive ordering. Align the implementation with the v1 spec so post-delivery confirmation depends on IO-local receive evidence captured at or after command acceptance, not on snapshot sequencing alone.

## Acceptance Criteria

Replay or out-of-order HA observations cannot confirm a command unless IO-local receive ordering proves the observation arrived after delivery; manual fan changes only resolve pending commands when delivery-local ordering is newer; tests cover both source seq and monotonic receive evidence.

