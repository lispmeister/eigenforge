---
id: eig-d3c0
status: open
deps: []
links: []
created: 2026-05-14T07:44:01Z
type: feature
priority: 2
assignee: lispmeister
---
# Spec §7/§2/§10/§13: lift actuator-state suppression out of the reasoner into Core.ActuatorGate

§7 calls the reasoner 'pluggable from the start' but assigns 'already in desired state' suppression to the V1 rules reasoner behavior. An LLM or other future reasoner should not have to reimplement safety suppression. Prose also conflicts across §2, §7, §10, §13 on who owns this check.

Proposed change: introduce a fixed Core.ActuatorGate stage between Reasoner and CapabilityChecker. Reasoner emits propose_action / propose_no_action / no_threshold_event / insufficient_fresh_data without considering current actuator state. ActuatorGate observes the latest fan state from the normalized snapshot and, for idempotent actuators, rewrites a propose_action whose requested_state already matches fan_state into propose_no_action with reason already_in_state. Update §2, §7, §10, §13, and golden trace 2 to agree on the new location. Code change is a follow-up ticket.

Critical files: apps/eigenforge_core/lib/eigenforge/core/reasoners/co2_rules.ex, apps/eigenforge_core/lib/eigenforge/core/reasoner.ex, apps/eigenforge_core/lib/eigenforge/core/policy_engine.ex

## Acceptance Criteria

§2 OODA flow names ActuatorGate as a distinct stage between Reasoner and CapabilityChecker. §7 reasoner outcome shapes unchanged but reasoner is no longer responsible for already-in-state check. §10 and §13 agree with §7 and §2 on the new location. Golden trace 2 still records propose_no_action with the same ledger event shape. Plan reviewed before any code change.


## Notes

**2026-05-14T07:57:04Z**

Spec updated: §1 OODA flow, §1 implementation order, §2 eigenforge_core responsibilities, §2 OTP layout, §7 Reasoner Interface, §7 outcome types, §7 Actuator-State Gate, §7 stale path, §13 trace runner flow, §13 golden trace 2, §13 core logic test rig all reference Core.ActuatorGate as a fixed stage. Code change is the follow-up — move actuator-state check out of co2_rules.ex and into a new Core.ActuatorGate module.
