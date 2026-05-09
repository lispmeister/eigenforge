---
id: eig-lmvx
status: closed
deps: []
links: []
created: 2026-05-09T13:39:43Z
type: task
priority: 1
assignee: lispmeister
---
# Rework prototype HTML for local SQLite spec

Update prototype-v1-spec.html so the visual spec matches the revised PROTOTYPE-V1-SPEC.md local SQLite per-core persistence and quorum/network split model.

## Acceptance Criteria

HTML no longer presents Postgres as the core ledger; local SQLite per core node is visible; finalization/consensus boundary and network split rules are represented; sensor telemetry remains external.


## Notes

**2026-05-09T13:45:42Z**

Updated prototype-v1-spec.html to match the revised spec: local SQLite per core node, single-core finalization, post-commit command delivery, external telemetry, quorum catch-up, and network split safety.
