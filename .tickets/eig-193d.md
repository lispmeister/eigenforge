---
id: eig-193d
status: open
deps: [eig-60h5, eig-ibl4]
links: []
created: 2026-05-08T13:33:14Z
type: feature
priority: 2
assignee: lispmeister
tags: [next-slice]
---
# Implement IO.SimulatorClient publishing normalized snapshots over PubSub

Spec §3 §6: reads JSON fixtures from config/simulator_snapshots, publishes on io_state:room:ROOM_ID and io_fault_status. Honors EIGENFORGE_IO_MODE=simulator; refuses outside connections.

## Acceptance Criteria

Starting umbrella in simulator mode produces snapshots that the core OODA pipeline consumes end-to-end. Simulator telemetry remains ephemeral and external to the core SQLite ledger; only finalized OODA facts and command-ledger events are persisted by core.

## Notes

**2026-05-09T14:00:32Z**

Aligned with revised spec: simulator telemetry remains ephemeral; only finalized OODA facts and command-ledger events are persisted by core.
