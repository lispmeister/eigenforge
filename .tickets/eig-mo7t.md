---
id: eig-mo7t
status: closed
deps: []
links: []
created: 2026-05-14T05:55:15Z
type: task
priority: 1
assignee: lispmeister
---
# Use snapshot fan observation before after-action fallback for effect_epoch (§9)

Spec §9 now fixes the precedence: use the current snapshot's `source_observation_ids.fan` when present, otherwise the latest terminal after-action id for that target, otherwise `startup`. The remaining work is to keep `CommandIssuer`, `SnapshotSubscriber`, and trace generation on the same priority order.

## Acceptance Criteria

`CommandIssuer` and the golden trace runner derive the same `effect_epoch` for a given room/target/action, with snapshot fan observation ids taking priority over projection fallbacks. Tests cover the snapshot-fan path, terminal-event fallback, and startup fallback.
