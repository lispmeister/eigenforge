---
id: eig-d3c0
status: closed
deps: []
links: []
created: 2026-05-14T07:44:01Z
type: feature
priority: 2
assignee: lispmeister
---
# Duplicate of eig-ag1x: implement Core.ActuatorGate between reasoner and capability check

The spec already places `Core.ActuatorGate` between the reasoner and capability checking. This ticket is now redundant with the higher-priority implementation ticket [eig-ag1x](/Users/fix/projects/claude-code/eigenforge/.tickets/eig-ag1x.md), which owns the code change.

Critical files: apps/eigenforge_core/lib/eigenforge/core/reasoners/co2_rules.ex, apps/eigenforge_core/lib/eigenforge/core/reasoner.ex, apps/eigenforge_core/lib/eigenforge/core/policy_engine.ex

## Acceptance Criteria

Closed as a duplicate of [eig-ag1x](/Users/fix/projects/claude-code/eigenforge/.tickets/eig-ag1x.md).

## Notes

**2026-05-15T13:23:15Z**

Closed as a duplicate of eig-ag1x; actuator-gate implementation is tracked there.
