---
id: eig-igam
status: open
deps: []
links: []
created: 2026-05-14T05:37:04Z
type: bug
priority: 1
assignee: lispmeister
---
# Introduce a dedicated recovery supervisor that resolves all pending commands before per-room subscribers start

The current recover_pending_commands/1 in SnapshotSubscriber queries all rooms with a non-null pending_command_id and resolves them as a side-effect of whichever subscriber happens to restart first. A room-a subscriber should not be responsible for timing out room-b's commands. The order of subscriber restarts determines which room's commands get recovered, which violates the spec §9 invariant that all pending commands must be classified or terminally resolved before any new physical commands are issued.

## Acceptance Criteria

- A new module (e.g. Eigenforge.Core.PendingCommandRecovery) queries latest_room_control_state for all rooms with a non-null pending_command_id at startup
- For each pending command it either immediately records a timed_out after_action_recorded event (if expired) or registers a supervised timer
- This recovery phase completes before any SnapshotSubscriber begins processing new snapshots from pubsub
- recover_pending_commands/1 in SnapshotSubscriber is removed or restricted to its own room_id only (no cross-room side effects)
- Existing two-room recovery test passes with the new design
- New test: two pending commands across two rooms are both resolved before either subscriber receives its first live snapshot

