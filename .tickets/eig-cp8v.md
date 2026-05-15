---
id: eig-cp8v
status: closed
deps: [eig-85hp]
links: [eig-85hp]
created: 2026-05-14T00:00:00Z
type: task
priority: 1
assignee: lispmeister
---
# Add Mailbox.CommandTransport and PubSubTransport (§9)

The spec (§9) requires an explicit behaviour:

```elixir
@callback publish_command(envelope :: map(), receipt :: map(), opts :: keyword()) ::
  {:ok, delivery_evidence :: map()} | {:error, reason :: term()}
```

with `Mailbox.PubSubTransport` as the V1 implementation. eig-85hp updated the spec to name this behaviour; this ticket implements it in code.

Currently `CommandPublisher.publish/3` directly dispatches via `Registry` without this abstraction. The spec's rationale is future replaceability with a direct GenServer call or an Oban-backed queue without changing the mailbox boundary contract.

Required changes:
1. Create `apps/eigenforge_mailbox/lib/eigenforge/mailbox/command_transport.ex` defining the `Mailbox.CommandTransport` behaviour with `publish_command/3`.
2. Create `apps/eigenforge_mailbox/lib/eigenforge/mailbox/pub_sub_transport.ex` implementing `Mailbox.CommandTransport` via Registry dispatch (extract the current Registry logic from `CommandPublisher`).
3. Update `CommandPublisher.publish/3` to call `transport.publish_command/3` where transport is injected (defaulting to `PubSubTransport`).
4. Update `HomeAssistantClient` and `SnapshotSubscriber` if they reference `CommandPublisher` directly in a way that bypasses the new boundary.
5. Add a test asserting that a substitute transport receives the correct `publish_command/3` call with the right arguments.

## Acceptance Criteria

- `Mailbox.CommandTransport` behaviour module exists with `publish_command/3` callback.
- `Mailbox.PubSubTransport` implements it via Registry dispatch.
- `CommandPublisher` delegates to the injected transport.
- Transport is overridable in tests.
- `mix test` green.
