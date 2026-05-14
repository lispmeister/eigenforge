---
id: eig-jyj0
status: open
deps: []
links: []
created: 2026-05-14T07:44:42Z
type: task
priority: 3
assignee: lispmeister
---
# Spec §6.4: replace runtime coalescing prose with a machine-checkable predicate

§6.4 says runtime coalesces repeated nominal/no-threshold snapshots by snapshot_hash and records the first nominal no-command decision after startup or after a transition from stale, threshold-breached, degraded, or command-pending state. For an auditability-focused system, 'may coalesce' and 'transition' without a machine-checkable predicate is loose.

Proposed change: replace the prose with an explicit predicate over latest_room_control_state — record a new policy_decision_recorded / reasoner_outcome_recorded for a nominal snapshot iff at least one of these projection fields differs from the latest committed decision: fan_state, source_status.co2, top-level freshness, pending_command_id, connection_status. Add a unit test that proves the predicate.

## Acceptance Criteria

§6.4 contains a numbered predicate, not prose. Unit test covers: startup → nominal A → nominal A (coalesced) → threshold → nominal A (recorded) → nominal A (coalesced). The predicate is implemented in SnapshotSubscriber or equivalent.


## Notes

**2026-05-14T07:57:04Z**

Spec updated: §6.4 now has a machine-checkable predicate over latest_room_control_state fields (fan_state, source_status.co2, freshness, pending_command_id, connection_status). Unit test covering startup→nominal→nominal(coalesced)→threshold→nominal(recorded) still needed.
