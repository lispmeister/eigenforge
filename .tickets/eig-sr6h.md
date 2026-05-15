---
id: eig-sr6h
status: closed
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 2
assignee: lispmeister
---
# Persist fan receive ordering in latest_room_control_state (INV-14)

`SnapshotSubscriber.pre_command_snapshot` (`snapshot_subscriber.ex:596–597`) reads:
```elixir
"source_received_seq" => %{"fan" => room_state["source_received_seq_fan"] || command.snapshot_seq},
"source_received_monotonic_ms" => %{"fan" => room_state["source_received_monotonic_ms_fan"]},
```

These column names are not written by `LedgerProjections.observe_snapshot` and are not in the spec's `latest_room_control_state` table definition (§11). Both reads silently return `nil`. This breaks post-delivery ordering evidence for after-action confirmation: `post_delivery_snapshot?/2` in `SnapshotSubscriber` compares source receive sequences, and a nil pre-command sequence means any post-command snapshot with a non-nil seq is treated as post-delivery, even if it predates command delivery.

Required changes:
1. Add `source_received_seq_fan INTEGER` and `source_received_monotonic_ms_fan INTEGER` columns to the `latest_room_control_state` CREATE TABLE in `LedgerProjections.init_sql/0`.
2. Write these fields from `NormalizedSnapshot.source_received_seq["fan"]` and `NormalizedSnapshot.source_received_monotonic_ms["fan"]` in `LedgerProjections.observe_snapshot/3`.
3. Update `LedgerProjections.rebuild/1` to handle existing databases missing these columns (add with `ALTER TABLE … ADD COLUMN IF NOT EXISTS`).
4. Add a test asserting that after an `observe_snapshot` call the correct fan seq values are retrievable from the projection.

## Acceptance Criteria

- `latest_room_control_state` table has both new columns.
- `observe_snapshot` writes correct values for each normalized snapshot.
- `SnapshotSubscriber.pre_command_snapshot` reads non-nil values when a prior snapshot has been observed.
- `mix test` green.
