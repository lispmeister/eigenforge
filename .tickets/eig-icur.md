---
id: eig-icur
status: open
deps: []
links: []
created: 2026-05-11T12:31:44Z
type: task
priority: 1
assignee: lispmeister
parent: eig-q25o
tags: [core, ledger, policy]
---
# Prove policy event cardinality for remaining V1 control paths

Add focused acceptance coverage for the remaining clarified V1 policy/control paths so exact durable event cardinality is proven for nominal no-threshold, already-in-state, stale or malformed deny, observe-only fault, and command-issued paths.

## Acceptance Criteria

Tests or golden traces assert exact durable event cardinality and capability_status or decision semantics for command-issued, already-in-state no-action, nominal no-threshold, stale deny, malformed deny, and observe-only fault paths.

