---
id: eig-fl9b
status: open
deps: [eig-ib5q]
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 2
assignee: lispmeister
---
# Add IO.FaultStatusLog as a dedicated debug log writer (§2 OTP layout, §6.3)

The spec (§2) lists `IO.FaultStatusLog` as a separate module. The spec (§6.3) says:

> "For debugging, IO also writes its IO fault/status stream to: `log/io_fault_status.log`. The path is configurable with `EIGENFORGE_IO_FAULT_STATUS_LOG`."

Currently the debug log writing is embedded in `Core.IoFaultStatus.append_debug_log` (wrong module boundary per eig-ib5q). After eig-ib5q moves fault publishing to `eigenforge_io`, the debug log writer should be a dedicated module rather than a private function.

Required changes (after eig-ib5q):
1. Create `apps/eigenforge_io/lib/eigenforge/io/fault_status_log.ex` as a GenServer or simple module that accepts fault events and appends them (with redaction) to the configured debug log path.
2. `IO.FaultStatus` (created in eig-ib5q) calls `IO.FaultStatusLog.append/2` instead of inlining the file write.
3. `IO.FaultStatusLog` handles `mkdir_p`, write errors (log locally, do not crash), and format encoding.
4. The path is read from `EIGENFORGE_IO_FAULT_STATUS_LOG` via `RuntimeConfig`.
5. Add a test asserting that a fault event is written to the log path in the expected format.

## Acceptance Criteria

- `IO.FaultStatusLog` module exists.
- Debug log writes go through it, not through inlined file calls.
- Log path is configurable and tested.
- `mix test` green.
