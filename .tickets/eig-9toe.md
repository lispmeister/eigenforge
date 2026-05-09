---
id: eig-9toe
status: open
deps: [eig-60h5]
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

Signing config/devices.json produces a sidecar the runtime accepts; missing/invalid sidecar fails startup in home_assistant mode and is permitted in simulator mode.

