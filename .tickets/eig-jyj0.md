---
id: eig-jyj0
status: closed
deps: []
links: []
created: 2026-05-14T07:44:42Z
type: task
priority: 2
assignee: lispmeister
---
# Apply the §6.4 nominal coalescing predicate

§6.4 now defines a machine-checkable predicate over `latest_room_control_state`. The remaining work is to apply that predicate in the runtime path so repeated nominal/no-threshold snapshots are coalesced only when the tracked decision inputs have not changed.

## Acceptance Criteria

Unit test covers: startup -> nominal A -> nominal A (coalesced) -> threshold -> nominal A (recorded) -> nominal A (coalesced). The predicate is implemented in `SnapshotSubscriber` or equivalent and matches the spec fields: `fan_state`, `source_status.co2`, freshness, `pending_command_id`, and `connection_status`.


## Notes

**2026-05-14T07:57:04Z**

Spec updated: §6.4 now has a machine-checkable predicate over latest_room_control_state fields (fan_state, source_status.co2, freshness, pending_command_id, connection_status). Unit test covering startup→nominal→nominal(coalesced)→threshold→nominal(recorded) still needed.
