---
id: eig-gm9l
status: closed
deps: []
links: []
created: 2026-05-14T05:02:14Z
type: task
priority: 3
assignee: lispmeister
---
# Remove nil default for pre_command_snapshot in AfterActionObserver.interpret_fault

interpret_fault/3 has pre_command_snapshot \\ nil, causing validate_observation_order to fall back to using command.snapshot_seq (the snapshot sequence number) as the ordering reference when no snapshot is provided. The spec (§10) requires ordering proof based on source_received_seq.fan or source_received_monotonic_ms.fan from the pre-command snapshot, not the snapshot sequence number. The nil default silently accepts faults with incorrect ordering evidence.

## Acceptance Criteria

- interpret_fault/3 signature requires pre_command_snapshot explicitly (no default nil)
- all callers in SnapshotSubscriber pass the pre_command_snapshot map
- validate_observation_order uses source_received_seq.fan / source_received_monotonic_ms.fan from the snapshot
- fault ordering test: a fault with seq equal to the pre-command fan seq is rejected as stale
- fault ordering test: a fault with seq greater than the pre-command fan seq is accepted

