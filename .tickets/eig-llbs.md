---
id: eig-llbs
status: closed
deps: [eig-p9ms]
links: []
created: 2026-05-08T13:32:45Z
type: chore
priority: 2
assignee: lispmeister
tags: [code-quality]
---
# Extract reasoner into Eigenforge.Core.Reasoner behaviour

The reasoner is private function clauses inside Eigenforge.Trace. Spec §7 requires a pluggable behaviour. Extract to lib/eigenforge/core/reasoner.ex with @behaviour and lib/eigenforge/core/reasoners/co2_rules.ex as the V1 impl.

## Acceptance Criteria

Reasoner tested independently without Trace; Trace calls the configured reasoner module; spec pluggability satisfied.


## Notes

**2026-05-10T05:09:27Z**

2026-05-10 spec clarification update: deterministic rules reasoner owns CO2 threshold evaluation and idempotent fan already-in-state propose_no_action; core must not rewrite reasoner outcomes in a separate actuator gate.
