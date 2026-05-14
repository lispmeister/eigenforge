---
id: eig-mo7t
status: open
deps: []
links: []
created: 2026-05-14T05:55:15Z
type: task
priority: 2
assignee: lispmeister
---
# Spec §9: clarify effect_epoch definition to distinguish snapshot fan observation id from terminal after_action_id

Spec §9 defines effect_epoch as 'the latest resolved actuator state observation id for the target from source_observation_ids.fan when known, otherwise the latest command lifecycle terminal event id for that target, otherwise startup.' The phrase 'latest resolved actuator state observation id' is ambiguous: it could mean the fan observation id from the current snapshot (present whenever IO reports fan state) or the after_action_id of the most recently closed command. The current implementation uses source_observation_ids.fan from the current snapshot first, then latest_after_action_id from the projection. This interpretation needs to be made explicit so the golden trace and runtime agree.

## Acceptance Criteria

PROTOTYPE-V1-SPEC.md §9 effect_epoch definition unambiguously states: (1) use source_observation_ids.fan from the triggering snapshot when the fan has been observed by IO, (2) otherwise use the latest_after_action_id from the room projection for that target, (3) otherwise startup. The golden trace runner and SnapshotSubscriber both implement the same priority order. A note explains why the snapshot's fan observation id takes priority over the projection's after_action_id.

