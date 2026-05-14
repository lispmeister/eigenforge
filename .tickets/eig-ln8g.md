---
id: eig-ln8g
status: open
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 4
assignee: lispmeister
---
# Add Mailbox.LedgerNotifier (§2 OTP layout)

The spec (§2) lists `Mailbox.LedgerNotifier` in the suggested OTP process layout. The spec (§11) states that projection subscribers should receive lightweight notifications:

> "Use local PubSub/process notifications only as wakeups for predefined decision/action subscriptions and dashboard updates. Notifications should carry lightweight identifiers… Consumers re-read from the local SQLite ledger or projection tables instead of treating notification payloads as authoritative history."

Currently there is no mailbox module that translates committed ledger events into lightweight delivery notifications. The dashboard and mailbox projection consumers have no structured notification path — they either poll or are absent.

Required changes:
1. Create `apps/eigenforge_mailbox/lib/eigenforge/mailbox/ledger_notifier.ex` that subscribes to committed ledger event signals from core and re-publishes lightweight `{:ledger_event_committed, event_id, event_type, core_node_id}` messages to interested mailbox subscribers.
2. Define what core signals trigger notifications (e.g., `command_envelope_issued`, `after_action_recorded`).
3. Consumers (dashboard, mailbox projections) receive the lightweight notification and re-read from SQLite.
4. Add a test asserting the correct notification shape is published when a ledger event is committed.

## Acceptance Criteria

- `Mailbox.LedgerNotifier` module exists.
- It publishes lightweight notifications (not full payloads) to subscribers.
- At least one consumer (e.g., `Dashboard.LiveView`) uses it.
- `mix test` green.
