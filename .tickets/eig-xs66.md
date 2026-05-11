---
id: eig-xs66
status: closed
deps: []
links: [eig-l5tk, eig-glzz, eig-5mvh]
created: 2026-05-11T11:47:11Z
type: bug
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [mailbox, v1-io, bug]
---
# Move receipt io_accepted transition after real adapter acceptance

Home Assistant command handling currently marks a receipt as io_accepted before attempting adapter dispatch. This can classify disconnected, disabled, duplicate, or failed commands as accepted and breaks restart recovery and after-action truth.

## Acceptance Criteria

Receipt phase remains receipt_stored or publish_attempted when adapter dispatch is rejected or fails before real IO acceptance; io_accepted is recorded only after adapter acceptance succeeds; tests cover not_connected, physical_control_disabled, duplicate idempotency key, transport failure, and successful acceptance paths.

