---
id: eig-9oxm
status: closed
deps: []
links: []
created: 2026-05-11T12:32:15Z
type: task
priority: 1
assignee: lispmeister
parent: eig-zohd
tags: [mailbox, recovery, io]
---
# Prove mailbox degraded-mode and restart recovery matrix

Add the remaining focused coverage for receipt-store corruption, crash windows, degraded-mode blocking, and pending-command classification across restart so mailbox and command-lifecycle recovery behavior is fully proven for V1.

## Acceptance Criteria

Tests cover corrupt or unverifiable receipt store entering degraded mode, no publish or redelivery while degraded, crash after receipt_stored, crash after publish_attempted, pending-command classification across receipt phases on restart, and IO degraded rejection when the command execution store is missing or unverifiable.

