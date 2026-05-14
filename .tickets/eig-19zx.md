---
id: eig-19zx
status: open
deps: []
links: []
created: 2026-05-14T05:54:02Z
type: bug
priority: 1
assignee: lispmeister
---
# Fix Trace.build_ledger stale path to emit policy_decision_recorded then stale_snapshot_denied as two separate events

Trace.event_type/1 (trace.ex:195) maps %PolicyDecision{decision: "deny_stale_snapshot"} to "stale_snapshot_denied" directly, producing one ledger event for the stale path. SnapshotSubscriber.append_payloads + append_stale_deny/3 emits two events: policy_decision_recorded then stale_snapshot_denied. The trace and runtime produce different ledger event sequences for the stale CO2 case. Any golden trace fixture for the stale path is wrong. No test currently catches this because the ooda_pipeline_test checks the runtime ledger, not trace output.

## Acceptance Criteria

Trace.build_ledger produces [reasoner_outcome_recorded, policy_decision_recorded, stale_snapshot_denied] for the stale CO2 fixture. Trace.event_type/1 no longer has a special clause for deny_stale_snapshot PolicyDecision. A stale golden trace fixture is committed and passes mix eigenforge.trace.verify. The ooda_pipeline_test stale acceptance test still passes.

