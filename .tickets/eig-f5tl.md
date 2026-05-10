---
id: eig-f5tl
status: closed
deps: [eig-9toe, eig-5b1u]
links: []
created: 2026-05-10T05:07:09Z
type: task
priority: 2
assignee: lispmeister
parent: eig-rql0
tags: [config, v1]
---
# Add sample runtime config and signed V1 fixtures

Add .env.example, sample config/devices.json with exactly one `active: true` room, sample capability grant path, and documented signing flow for V1. Simulator snapshot fixtures may remain unsigned; normal device inventory and capability grants stay signed in both runtime modes.

## Acceptance Criteria

.env.example contains required mode, HA, HMAC, IO log, core node, and DB path placeholders; sample devices/capability config validates against schemas including active room selection; docs or task output show how to sign them without committing secrets.
