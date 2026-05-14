---
id: eig-cx4m
status: open
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 4
assignee: lispmeister
---
# Extract IO.CommandExecutor from HomeAssistantClient (§2 OTP layout)

The spec (§2) lists `IO.CommandExecutor` as a distinct module. Currently command verification and dispatch logic is embedded in `HomeAssistantClient.verify_and_dispatch/2` and `HomeAssistantClient.dispatch_command/2` (`home_assistant_client.ex:231–339`), coupling command execution to the WebSocket connection process.

Extracting it:
- separates the command validation/dispatch contract from the HA-connection lifecycle;
- makes command executor logic testable without a live transport;
- aligns with the spec's boundary where `IO.CommandExecutor` receives command envelopes through the mailbox boundary and executes via the configured adapter.

Required changes:
1. Create `apps/eigenforge_io/lib/eigenforge/io/command_executor.ex` with an `execute/2` or `execute/3` function that accepts a verified command envelope plus adapter config and performs the dispatch.
2. Move `verify_and_dispatch` and `dispatch_command` logic from `HomeAssistantClient` into `IO.CommandExecutor`.
3. `HomeAssistantClient.handle_info` for `{:mailbox_command, …}` delegates to `IO.CommandExecutor`.
4. Ensure `CommandExecutionStore` idempotency check remains in the executor.
5. Add unit tests for `IO.CommandExecutor` covering fan dispatch, stub targets, duplicate key rejection, and unsupported target.

## Acceptance Criteria

- `IO.CommandExecutor` module exists and is tested independently.
- `HomeAssistantClient` delegates command dispatch to it.
- `mix test` green.
