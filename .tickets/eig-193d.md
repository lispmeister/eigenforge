---
id: eig-193d
status: closed
deps: [eig-60h5, eig-ibl4, eig-tzyb]
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

Starting umbrella in simulator mode produces snapshots with deterministic `source_observation_ids`, `source_received_seq`, and `source_received_monotonic_ms` that the core OODA pipeline consumes end-to-end. Simulator telemetry remains ephemeral and external to the core SQLite ledger; only finalized OODA facts and command-ledger events are persisted by core.

## Notes

**2026-05-09T14:00:32Z**

Aligned with revised spec: simulator telemetry remains ephemeral; only finalized OODA facts and command-ledger events are persisted by core.

**2026-05-10T05:09:28Z**

2026-05-10 spec clarification update: simulator snapshots must publish clarified snapshot_seq, snapshot_hash, top-level CO2 control freshness, and contract-valid safety snapshots for representable malformed/missing CO2.

**2026-05-10T05:37:39Z**

SPEC-V1-FIXES-003 applied: simulator fixtures are unsigned but must include fixture_schema_id, fixture_schema_version, scenario id, and intentional malformed-field/omission metadata for malformed fixture tests.
