---
id: eig-ad2p
status: closed
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 2
assignee: lispmeister
---
# Add IO.AdapterSupervisor (§2 OTP layout)

The spec (§2) lists `IO.AdapterSupervisor` in the suggested OTP process layout. Currently `IO.Application` starts adapters (`HomeAssistantClient` or `SimulatorClient`) directly under `IO.Supervisor` with no intermediate supervisor for the adapter subtree.

Adding an adapter supervisor:
- isolates adapter crashes from the rest of the IO supervision tree;
- makes the runtime mode switchable at a well-defined boundary;
- prepares the layout for V2 where multiple adapters might run concurrently.

Required changes:
1. Create `apps/eigenforge_io/lib/eigenforge/io/adapter_supervisor.ex` as a `Supervisor` that starts the mode-appropriate adapter child (`HomeAssistantClient` or `SimulatorClient`) based on `io_mode`.
2. Replace direct adapter children in `IO.Application.children/1` with `{IO.AdapterSupervisor, config}`.
3. Confirm restart strategy (`:one_for_one` is sufficient for V1).
4. Update tests that start `HomeAssistantClient` or `SimulatorClient` directly to use the supervisor where appropriate.

## Acceptance Criteria

- `IO.AdapterSupervisor` module exists and is the parent of adapter processes.
- `IO.Application` starts `IO.AdapterSupervisor`, not adapter children directly.
- `mix test` green.
