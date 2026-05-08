---
id: eig-fu4o
status: closed
deps: [eig-1867]
links: []
created: 2026-05-08T12:57:42Z
type: task
priority: 0
assignee: lispmeister
---
# Implement simulator-backed golden trace slice

Implement the co2_high_fan_off, co2_high_fan_on, and co2_stale_fan_off simulator trace paths from fixture through reasoner, capability, policy, ledger event chain, command/delivery receipt where applicable, simulated IO, after-action, and verification.

## Acceptance Criteria

mix eigenforge.trace.run and mix eigenforge.trace.verify pass for the first three simulator fixtures

