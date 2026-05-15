---
id: eig-iz79
status: closed
deps: []
links: []
created: 2026-05-14T05:54:52Z
type: chore
priority: 2
assignee: lispmeister
---
# Replace SnapshotSubscriber event_type/1 conds with function heads

SnapshotSubscriber.event_type/1 (snapshot_subscriber.ex:740-748) uses a cond block with module equality checks and no catch-all clause. An unknown struct raises CondClauseError with no useful diagnostic. Trace.event_type/1 uses pattern-matched function heads, which produces FunctionClauseError with the actual struct value and is consistent with idiomatic Elixir.

## Acceptance Criteria

SnapshotSubscriber.event_type/1 uses pattern-matched function heads (defp event_type(%ReasonerOutcome{}), etc.). All existing tests pass.
