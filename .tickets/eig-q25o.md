---
id: eig-q25o
status: open
deps: [eig-ibl4, eig-tzyb, eig-icur]
links: []
created: 2026-05-10T05:06:54Z
type: feature
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [next-slice, core, ledger]
---
# Implement V1 policy outcomes and control-path event cardinality

Implement clarified policy/control-path behavior: no_command with capability_status=not_checked for no-action/no-threshold paths, stale CO2 sequence with skipped capability check and deny_stale_snapshot, required vs optional durable events by command/no-action/stale/fault/connection path, and duplicate prevention per source observation plus correlation id.

## Acceptance Criteria

Golden traces or focused tests assert exact ledger event cardinality for command issued, already-in-state no-action, nominal no-threshold, stale/malformed CO2 deny, observe-only sensor fault, and outside connection transition paths.


## Notes

**2026-05-10T05:23:41Z**

SPEC-V1-FIXES-002 applied: control-path implementation must include decision cadence/dedupe, coalesced repeated nominal runtime snapshots, in-flight command suppression by effect_key, and restart recovery behavior.
