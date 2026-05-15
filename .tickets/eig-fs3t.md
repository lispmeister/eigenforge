---
id: eig-fs3t
status: open
deps: [eig-ib5q]
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 2
assignee: lispmeister
---
# Add Core.FaultStatusSubscriber as a dedicated process (§2 OTP layout)

The spec (§2) lists `Core.FaultStatusSubscriber` as a distinct process in the suggested OTP layout. Currently, fault status subscription is handled inside `SnapshotSubscriber.init/1` (via `subscribe_faults/1`) and `handle_info({:io_fault_status, event}, state)`. Mixing two subscriptions into one process couples snapshot processing and fault observation lifetimes.

A dedicated subscriber:
- has its own restart semantics independent of snapshot processing;
- holds only the state it needs (ledger writer reference, room context);
- makes the fault→ledger persistence path testable in isolation.

Required changes:
1. Create `apps/eigenforge_core/lib/eigenforge/core/fault_status_subscriber.ex` as a GenServer that subscribes to the IO fault/status topic and handles selective ledger persistence for OODA-relevant faults.
2. Remove the `subscribe_faults` call and `handle_info({:io_fault_status, …})` clause from `SnapshotSubscriber`.
3. Start `Core.FaultStatusSubscriber` in `Core.Application`.
4. If after-action fault resolution (currently in `maybe_resolve_pending_from_fault/2`) requires access to `SnapshotSubscriber` state, design a clean inter-process coordination mechanism (e.g., a message or a shared projection read).
5. Add tests for the fault subscriber in isolation.

## Acceptance Criteria

- `Core.FaultStatusSubscriber` module exists and is supervised.
- `SnapshotSubscriber` no longer subscribes to or handles fault status events.
- Fault-driven after-action resolution still works end-to-end.
- `mix test` green.
