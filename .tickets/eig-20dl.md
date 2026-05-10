---
id: eig-20dl
status: closed
deps: []
links: []
created: 2026-05-08T13:32:45Z
type: chore
priority: 2
assignee: lispmeister
tags: [code-quality]
---
# Fix O(n^2) accumulator in build_ledger

trace.ex build_ledger uses events ++ [event] in a reduce body (O(n^2)) and List.last/1 for causation_id (O(n)). Accumulate reversed and track last event ID explicitly while preserving node-local sequence order, previous_event_hash links, and consensus metadata.

## Acceptance Criteria

Behavior unchanged; golden traces still match; no ++ [event] or List.last in the reduce body; ledger events remain ordered by local sequence and retain `core_node_id`, `consensus_decision_id`, `consensus_status`, and `quorum_ref`.

## Notes

**2026-05-09T14:00:32Z**

Aligned with revised spec: performance fix must preserve node-local sequence order, previous hash links, and consensus metadata in generated ledger events.
