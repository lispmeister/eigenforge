---
id: eig-431e
status: open
deps: []
links: []
created: 2026-05-11T12:31:36Z
type: task
priority: 1
assignee: lispmeister
parent: eig-7vfe
tags: [core, io, timing]
---
# Replace wall-clock runtime deadlines with monotonic timers

Finish the runtime timing migration for V1 by replacing wall-clock duration checks with monotonic timers while preserving canonical UTC timestamps for persisted records and conservative restart handling from persisted UTC deadlines.

## Acceptance Criteria

Focused tests cover command expiry, source freshness age, reconnect backoff, and after-action timeout behavior under wall-clock jumps; restart recovery uses persisted UTC deadlines conservatively and does not issue equivalent commands before pending work is classified terminally.

