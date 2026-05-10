---
id: eig-9toe
status: closed
deps: [eig-60h5, eig-p9ms]
links: []
created: 2026-05-08T13:33:14Z
type: feature
priority: 2
assignee: lispmeister
tags: [next-slice]
---
# Implement mix eigenforge.config.sign and mix eigenforge.capability.grant

Spec §4: detached .sig sidecars with payload_hash, signature_version, signature. Capability grant task writes JSON + sidecar from CLI args (subject, target, action, scope).

## Acceptance Criteria

Signing config/devices.json and capability grant JSON produces sidecars the runtime accepts. Missing/invalid sidecars fail startup in both home_assistant and simulator runtime modes; only static simulator snapshot fixtures may be unsigned.


## Notes

**2026-05-10T05:09:36Z**

2026-05-10 spec clarification update: signing helpers remain required for normal device inventory and capability grants in both home_assistant and simulator modes; unsigned allowance applies only to static simulator snapshot fixtures.
