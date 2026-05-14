---
id: eig-weaz
status: closed
deps: []
links: []
created: 2026-05-14T05:01:53Z
type: bug
priority: 2
assignee: lispmeister
---
# Read core_node_id from RuntimeConfig in CommandIssuer instead of hardcoded module attribute

CommandIssuer hardcodes @core_node_id "core_a" as a module attribute. The spec (§4, §9) requires this to come from EIGENFORGE_CORE_NODE_ID so that idempotency keys are node-specific. Running with a different node id will silently produce wrong idempotency keys that collide with core_a keys.

## Acceptance Criteria

- CommandIssuer.issue/6 accepts core_node_id via opts or reads it from RuntimeConfig
- idempotency_key derivation uses the runtime node id, not the atom 'core_a'
- CommandIssuer tests pass a node_id and assert it appears in the canonical payload
- EIGENFORGE_CORE_NODE_ID env var is plumbed through to CommandIssuer via SnapshotSubscriber opts

