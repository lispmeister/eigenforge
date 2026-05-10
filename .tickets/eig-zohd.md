---
id: eig-zohd
status: open
deps: [eig-xtqn, eig-glzz]
links: []
created: 2026-05-10T05:23:08Z
type: feature
priority: 0
assignee: lispmeister
parent: eig-rql0
tags: [next-slice, core, mailbox, io]
---
# Implement V1 command lifecycle in-flight guard and restart recovery

Implement command runtime semantics from the patched V1 spec: command lifecycle states including receipt delivery phases, effect_key derivation from source_observation_ids.fan or terminal lifecycle events, one in-flight command per physical effect, restart recovery matrix, pending command timeout recovery, conservative wall-clock restart handling, and IO durable command execution store keyed by idempotency_key.

## Acceptance Criteria

Tests cover duplicate snapshot dedupe, duplicate effect_key suppression, command lifecycle projection states, core restart with pending command, receipt_stored/publish_attempted/io_accepted recovery branches, restart after wall-clock jump with persisted UTC deadlines, IO restart with persisted duplicate idempotency_key, and IO degraded rejection when command execution store is missing or unverifiable.


## Notes

**2026-05-10T05:37:28Z**

SPEC-V1-FIXES-003 applied: restart recovery must honor the no autonomous recovery command invariant and classify or terminally resolve pending room/target/effect work before issuing an equivalent new physical command.
