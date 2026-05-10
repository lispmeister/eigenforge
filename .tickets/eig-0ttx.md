---
id: eig-0ttx
status: closed
deps: [eig-cj5v, eig-o1sj]
links: []
created: 2026-05-10T05:07:24Z
type: feature
priority: 2
assignee: lispmeister
parent: eig-rql0
tags: [v1-io, ledger]
---
# Implement connection transition persistence

Persist outside connection state transitions observed by core as connection_status_observed ledger events. Clarified spec treats connection_up, connection_down, reconnecting, degraded, and recovered as always OODA-relevant; other IO faults remain conditional on decision context.

## Acceptance Criteria

Core persists exactly one connection_status_observed event per observed transition/correlation; observe-only sensor faults are not persisted unless promoted for OODA/operator audit; tests cover conditional vs mandatory persistence.

