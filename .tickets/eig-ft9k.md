---
id: eig-ft9k
status: closed
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 1
assignee: lispmeister
---
# Map IO fault types to command rejection reasons

`HomeAssistantClient.handle_info` for `{:mailbox_command, topic, delivery}` contains:

```elixir
fault_type = if reason == :command_expired, do: "command_expired", else: "adapter_execution_failed"
```

This means:
- `:duplicate_idempotency_key` → published as `"adapter_execution_failed"` (wrong)
- `:invalid_command_signature` → published as `"adapter_execution_failed"` (wrong)

The spec (§6.2, §9) and the schema (`io_fault_status_event.schema.json`) define all three as distinct enum values: `"duplicate_idempotency_key"`, `"invalid_command_signature"`, `"command_expired"`. Using the wrong fault type breaks INV-10 (wrong-purpose-label rejection visibility), prevents operators from distinguishing replay attacks from expiry, and breaks any tooling that filters on these enum values.

Required changes:
1. Replace the binary `if` in `HomeAssistantClient` (`home_assistant_client.ex` around line 211) with a case or mapping that covers all three error atoms: `:command_expired`, `:duplicate_idempotency_key`, `:invalid_command_signature`.
2. Verify that `verify_delivery/3` returns each of these atoms for the corresponding failure mode.
3. Add tests for each fault path asserting the correct `fault_type` is published to `IoFaultStatus`.

## Acceptance Criteria

- A command rejected for expired envelope publishes `fault_type="command_expired"`.
- A duplicate idempotency key publishes `fault_type="duplicate_idempotency_key"`.
- An invalid signature publishes `fault_type="invalid_command_signature"`.
- All three cases tested.
- `mix test` green.
