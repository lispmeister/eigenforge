---
id: eig-nu0t
status: closed
deps: [eig-9toe, eig-c2fz]
links: []
created: 2026-05-10T05:07:09Z
type: feature
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [next-slice, core, config]
---
# Load signed capability grants and expose policy grant lookup

Load signed capability grants at startup, validate sidecar signatures and schema ids/versions, expose grant lookup for Core.PolicyEngine, and support not_checked policy status for paths that do not propose physical execution.

## Acceptance Criteria

Valid fan grant allows command_actuator for room:placeholder; missing/invalid grant produces deny_missing_capability or deny_invalid_capability; stale/no-command/no-threshold paths do not require a capability grant and record capability_status=not_checked.

