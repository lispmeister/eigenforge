---
id: eig-wyul
status: open
deps: [eig-p9ms]
links: []
created: 2026-05-10T05:07:24Z
type: feature
priority: 3
assignee: lispmeister
parent: eig-rql0
tags: [v1-io, deferred]
---
# Implement non-fan actuator stubs

Implement V1 placeholder adapter behavior for light, laser, and piezo beeper stubs. Only fan executes physically; stub actions return without physical action while preserving policy behavior for unsupported or non-idempotent/safety-sensitive actuator state.

## Acceptance Criteria

Stub targets never perform physical IO; policy denies blind commands for unknown/stale non-idempotent actuator state; noop_stub behavior is covered by tests or trace fixtures.

