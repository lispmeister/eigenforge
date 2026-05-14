---
id: eig-k4nj
status: closed
deps: []
links: []
created: 2026-05-14T04:44:06Z
type: bug
priority: 1
assignee: lispmeister
---
# Preserve snapshot retryability after pipeline failure

SnapshotSubscriber currently marks snapshot ids as processed even when run_pipeline/2 fails. That can turn a transient persistence or publish failure into a permanent drop on retry.

## Acceptance Criteria

When run_pipeline/2 returns an error, the snapshot id is not added to processed_snapshot_ids; a later replay of the same snapshot id is retried; tests cover both successful dedupe and retry-after-failure behavior.

