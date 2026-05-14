---
id: eig-a3xy
status: open
deps: []
links: []
created: 2026-05-14T05:54:09Z
type: bug
priority: 1
assignee: lispmeister
---
# Add source_received_seq_fan and source_received_monotonic_ms_fan columns to latest_room_control_state projection

pre_command_snapshot/2 in snapshot_subscriber.ex:595 reads room_state["source_received_seq_fan"] and room_state["source_received_monotonic_ms_fan"], but these columns do not exist in the latest_room_control_state DDL (ledger_projections.ex:330-374). Both are always nil after recovery, so the fan receive seq falls back to command.snapshot_seq (a snapshot ordinal). validate_observation_order then compares IO-local receive counters against a snapshot ordinal — the ordering evidence used in post-recovery confirmation is wrong. No test currently exercises this code path.

## Acceptance Criteria

latest_room_control_state DDL includes source_received_seq_fan INTEGER and source_received_monotonic_ms_fan INTEGER columns. observe_snapshot/3 populates them from snapshot.source_received_seq["fan"] and snapshot.source_received_monotonic_ms["fan"]. pre_command_snapshot/2 reads the correct column values. A test verifies that post-recovery ordering uses fan IO-local receive seq, not snapshot_seq. Projection rebuild correctly populates fan-seq columns from ledger-derived snapshot data where available.

