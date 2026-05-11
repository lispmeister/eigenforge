---
id: eig-7vfe
status: open
deps: [eig-777e, eig-tzyb, eig-xtqn, eig-23ow, eig-431e]
links: []
created: 2026-05-10T05:36:54Z
type: task
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [core, io, trace]
---
# Implement V1 monotonic runtime duration clocks

Use monotonic time for in-process runtime duration checks while preserving canonical UTC timestamps for signed records. Apply to command expiry, source freshness age, reconnect backoff, and after-action timeouts; wall-clock jumps must not break running duration logic. Across restart, use persisted canonical UTC deadlines conservatively because monotonic clocks are process-local.

## Acceptance Criteria

Tests simulate wall-clock jumps and verify command expiry, source freshness, reconnect backoff, and after-action timeout behavior follows monotonic durations while emitted timestamps remain canonical UTC. Restart tests verify persisted UTC command expiry/after-action deadlines are honored conservatively and no equivalent physical command is issued before pending work is terminally classified.
