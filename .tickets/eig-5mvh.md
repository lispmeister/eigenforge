---
id: eig-5mvh
status: open
deps: [eig-glzz, eig-zohd]
links: [eig-xs66, eig-l5tk, eig-glzz]
created: 2026-05-10T05:36:54Z
type: feature
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [mailbox, recovery, next-slice]
---
# Implement V1 mailbox receipt store and recovery

Persist signed delivery receipts and minimal routing metadata before publishing commands to IO. Initialize a signed receipt-store manifest on first startup; after initialization, a missing/corrupt/unverifiable store starts degraded and does not publish or redeliver commands until repaired or explicitly reset in simulator/test mode. Track delivery phases as receipt-store metadata (`receipt_stored`, `publish_attempted`, `io_accepted`) without mutating immutable signed receipt payloads.

## Acceptance Criteria

Tests cover first-start manifest initialization, receipt persisted before command publish, immutable signed receipt bodies, phase metadata rebuild on restart, crash after `receipt_stored` before `publish_attempted`, crash after `publish_attempted` before `io_accepted`, corrupted receipt store degraded mode, no publish/redelivery while degraded, and recovery interaction with pending command classification.
