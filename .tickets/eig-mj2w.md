---
id: eig-mj2w
status: open
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 4
assignee: lispmeister
---
# Add Mailbox.Projections (§2 OTP layout, §9)

The spec (§2) lists `Mailbox.Projections` in the suggested OTP process layout:

> "Maintains read projections only as mechanical read models over committed ledger records; projections do not grant authority or reinterpret events."

Currently the mailbox has no projection layer. The receipt store (`ReceiptStore`) is the only persistent mailbox state. A `Mailbox.Projections` module would provide a queryable read model over delivery phase and receipt state for the dashboard and for recovery.

Required changes:
1. Create `apps/eigenforge_mailbox/lib/eigenforge/mailbox/projections.ex` with query functions over the receipt store (e.g., `pending_commands/0`, `delivery_status/1`, `receipts_for_command/1`).
2. The projections are read-only derived views; they must not write to or reinterpret the ledger.
3. `Dashboard.ReadModel` and recovery logic in `SnapshotSubscriber` should use `Mailbox.Projections` rather than calling `ReceiptStore.entries_for_command` directly.
4. Add tests covering the projection queries.

## Acceptance Criteria

- `Mailbox.Projections` module exists with at least `pending_commands/0` and `delivery_status/1`.
- Dashboard and recovery use it as the query interface.
- `mix test` green.
