---
id: eig-gf4x
status: closed
deps: []
links: []
created: 2026-05-18T12:48:27Z
type: bug
priority: 2
assignee: lispmeister
---
# Guard SnapshotSubscriber against nil db_path in simulator mode

SnapshotSubscriber should not query LedgerProjections or read room projections when db_path is nil. Simulator and trace harnesses need a no-DB path that returns {:ok, nil} and skips DB-backed coalescing/projection reads.

## Acceptance Criteria

SnapshotSubscriber does not crash when db_path is nil; simulator-backed and trace tests run without a durable core DB path; fetch_room_state and snapshot observation writes are no-ops in nil-db mode.

