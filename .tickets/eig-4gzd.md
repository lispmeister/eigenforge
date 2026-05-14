---
id: eig-4gzd
status: closed
deps: []
links: []
created: 2026-05-14T04:44:06Z
type: bug
priority: 1
assignee: lispmeister
---
# Add terminal-event fallback to effect_key derivation

CommandIssuer.effect_key currently falls back from the fan observation id directly to startup. The spec requires effect_epoch to use the latest command lifecycle terminal event id when no resolved actuator observation exists, with startup as the final fallback.

## Acceptance Criteria

Equivalent commands after a terminal after-action derive a different effect_key from the previous in-flight command when the latest resolved actuator observation is absent; startup remains the final fallback; tests cover terminal-event-based effect_epoch selection and duplicate suppression after command completion.

