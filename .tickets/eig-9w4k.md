---
id: eig-9w4k
status: closed
deps: []
links: []
created: 2026-05-11T12:31:52Z
type: task
priority: 1
assignee: lispmeister
parent: eig-zp2l
tags: [home-assistant, io, after-action]
---
# Cover Home Assistant manual-state and replay confirmation edge cases

Add focused V1 acceptance coverage for manual or external Home Assistant fan state changes, replayed old events, and pending-command resolution rules that depend on IO-local receive ordering rather than source wall time alone.

## Acceptance Criteria

Tests prove REST success is accepted-not-confirmed, replayed older HA events cannot confirm a command, manual HA fan changes update live state and effect epoch, and a pending command resolves or contradicts only when IO-local ordering shows the observation arrived after delivery.

