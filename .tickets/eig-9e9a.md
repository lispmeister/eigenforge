---
id: eig-9e9a
status: closed
deps: []
links: []
created: 2026-05-14T05:02:01Z
type: bug
priority: 1
assignee: lispmeister
---
# Emit policy_decision_recorded and stale_snapshot_denied as two separate ledger events on stale CO2 path

SnapshotSubscriber.event_type/1 maps PolicyDecision{decision: 'deny_stale_snapshot'} to the event type 'stale_snapshot_denied', replacing the policy_decision_recorded event entirely. The spec (§11 event cardinality table) requires three events for the stale path: reasoner_outcome_recorded, policy_decision_recorded, AND stale_snapshot_denied. The policy decision event is currently lost.

## Acceptance Criteria

- stale CO2 pipeline appends three events: reasoner_outcome_recorded, policy_decision_recorded, stale_snapshot_denied
- policy_decision_recorded carries decision='deny_stale_snapshot' and capability_status='not_checked'
- stale_snapshot_denied is a separate summary event with the same correlation_id
- golden trace acceptance test 3 asserts all three event types in order
- ledger verification passes for the stale path

