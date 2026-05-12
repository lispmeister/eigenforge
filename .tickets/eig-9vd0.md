---
id: eig-9vd0
status: closed
deps: []
links: []
created: 2026-05-12T08:24:27Z
type: bug
priority: 1
assignee: lispmeister
tags: [core, ledger, command]
---
# Add terminal-event fallback to effect_key derivation

CommandIssuer.effect_key currently falls back from the fan observation id directly to startup. The v1 spec requires the effect epoch to fall back to the latest command lifecycle terminal event id when no resolved actuator observation exists, so equivalent work after a completed command hashes to the correct physical-effect boundary.

## Acceptance Criteria

Equivalent commands after a terminal after-action derive a different effect_key from the previous in-flight command when the latest resolved actuator observation is absent; startup remains the final fallback; tests cover terminal-event-based effect_epoch selection and duplicate suppression after command completion.

