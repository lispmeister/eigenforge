---
id: eig-3d13
status: closed
deps: []
links: []
created: 2026-05-09T13:28:32Z
type: task
priority: 1
assignee: lispmeister
---
# Rework prototype V1 spec for local SQLite quorum persistence

Update PROTOTYPE-V1-SPEC.md to assume each core node has a local SQLite decision ledger, persists post-consensus actions locally, keeps sensor/actuator data external, and documents quorum/network split implications.

## Acceptance Criteria

Spec no longer centers V1 on Postgres for core decision persistence; local SQLite per core node is explicit; consensus/finalized decision persistence and network partition behavior are documented; IO telemetry remains external.


## Notes

**2026-05-09T13:31:55Z**

Reworked PROTOTYPE-V1-SPEC.md around local SQLite per core node, one-member V1 finalization, post-quorum V2 persistence, external telemetry storage, and network split/catch-up safety rules.
