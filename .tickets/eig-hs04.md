---
id: eig-hs04
status: closed
deps: [eig-o1sj]
links: []
created: 2026-05-09T14:11:04Z
type: feature
priority: 2
assignee: lispmeister
tags: [next-slice]
---
# Implement local SQLite projections

Implement latest_room_control_state and recent_control_chains as mutable projection tables derived from node-local append-only ledger_events. Projections are convenience read models only and may be rebuilt.

## Acceptance Criteria

Projection updates never modify ledger_events; rebuild from ledger produces equivalent projection state; dashboard/read APIs treat ledger as authoritative on conflict. Projections include scaled sensor fields, pending_command_id, pending_effect_key, effect_key in recent chains, and command lifecycle/freshness display state needed by the clarified spec.


## Notes

**2026-05-10T05:09:58Z**

2026-05-10 spec clarification update: projections are mutable read models over the append-only ledger and live streams; include clarified latest_room_control_state fields and do not treat notifications as authoritative history.
