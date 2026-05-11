---
id: eig-runa
status: closed
deps: []
links: [eig-l5tk, eig-zp2l, eig-xtqn]
created: 2026-05-11T11:47:16Z
type: bug
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [after-action, home-assistant, bug]
---
# Carry IO-local ordering metadata through fault-driven after-action handling

Core fault-driven after-action handling currently drops source_received_seq/source_received_monotonic_ms from IO fault events, so adapter_rejected and adapter_failed terminal outcomes cannot be proven post-delivery in the live runtime path.

## Acceptance Criteria

IO fault/status events include the ordering fields needed for post-delivery proof when applicable; SnapshotSubscriber passes those fields into after-action fault interpretation; runtime tests demonstrate adapter_rejected and adapter_failed terminal after-actions can be recorded from live fault streams only when ordering evidence is newer than the command acceptance evidence.

