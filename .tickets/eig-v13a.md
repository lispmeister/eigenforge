---
id: eig-v13a
status: open
deps: []
links: []
created: 2026-05-11T12:31:59Z
type: task
priority: 2
assignee: lispmeister
parent: eig-x020
tags: [simulator, acceptance, trace]
---
# Expand simulator and fault-injection acceptance matrix

Complete the remaining V1 acceptance matrix by adding coverage for the outstanding simulator fixtures and the remaining fault or restart scenarios called out by the spec.

## Acceptance Criteria

Golden traces or focused acceptance tests cover co2_low_fan_on, co2_nominal_fan_off, co2_malformed, invalid or missing capability deny, invalid signature or receipt rejection, mailbox crash after receipt_stored, mailbox crash after publish_attempted, old observation replay, manual HA fan change during a pending command, and pending-command restart recovery.

