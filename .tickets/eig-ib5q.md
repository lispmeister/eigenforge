---
id: eig-ib5q
status: open
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 2
assignee: lispmeister
---
# Move IoFaultStatus into eigenforge_io (§2 boundary)

The spec (§2) assigns the IO fault/status stream to `eigenforge_io`:

> "`eigenforge_io` owns the outside-world boundary… Publishes the live IO stream and the IO fault/status stream… Writes its IO fault/status stream to a local debug file."
> "`eigenforge_core` owns the OODA loop… Observes IO state/faults after command delivery."

`Core.IoFaultStatus` (`apps/eigenforge_core/lib/eigenforge/core/io_fault_status.ex`) currently handles both IO-originated fault publishing and debug log writing, which are IO responsibilities. Core apps also call `Core.IoFaultStatus.record/2` directly for IO events, blurring the boundary that §2 uses to define V2 quorum isolation.

Required changes:
1. Create `apps/eigenforge_io/lib/eigenforge/io/fault_status.ex` (or `IO.FaultStatusLog`) that owns PubSub publishing, debug log writing, and fault event construction.
2. Move the `append_debug_log`, `publish`, and event construction logic from `Core.IoFaultStatus` to the IO module.
3. `eigenforge_core` retains a subscriber module (`Core.IoFaultStatus` or `Core.FaultStatusSubscriber`) that subscribes to the stream and handles selective ledger persistence — but does not write the debug log or construct the event.
4. Update application supervisors so `IO.FaultStatus` starts in `eigenforge_io` and `Core.FaultStatusSubscriber` starts in `eigenforge_core`.
5. Confirm all existing tests still pass with the moved module.

## Acceptance Criteria

- IO fault/status event construction, PubSub publishing, and debug log writing live in `eigenforge_io`.
- `eigenforge_core` only subscribes and selectively persists.
- `mix test` green.
