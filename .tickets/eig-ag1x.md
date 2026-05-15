---
id: eig-ag1x
status: closed
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 1
assignee: lispmeister
---
# Add Core.ActuatorGate between reasoner and capability check

The spec (§7) is explicit: "The reasoner module itself only produces `propose_action`, `no_threshold_event`, and `insufficient_fresh_data`. `Core.ActuatorGate` observes the raw reasoner result and, when `propose_action` would be redundant (fan already in the requested state for idempotent actuators), rewrites it to `propose_no_action` before the outcome is recorded or passed to capability checking."

Currently `Co2Rules` (`apps/eigenforge_core/lib/eigenforge/core/reasoners/co2_rules.ex:38–76`) checks fan state itself and directly returns `propose_no_action`. There is no `Core.ActuatorGate` module. The pipeline in `SnapshotSubscriber.run_pipeline` has no gate step.

This violates the spec's separation of concerns and means any future reasoner (LLM or otherwise) must re-implement the gate logic itself, which the spec explicitly prevents.

Required changes:
1. Create `apps/eigenforge_core/lib/eigenforge/core/actuator_gate.ex` implementing the gate: if reasoner returns `propose_action` and the fan is already in the requested state (idempotent actuator), rewrite to `propose_no_action` with the specified reason string; pass `propose_action` through for unknown/stale fan state on idempotent actuators; emit `propose_no_action` with `denied_unknown_non_idempotent_actuator_state` for non-idempotent actuators with unknown/stale state.
2. Strip the fan-state pattern matches from `Co2Rules` (`co2_rules.ex:38–45`, `co2_rules.ex:58–64`) so it only returns `propose_action`, `no_threshold_event`, and `insufficient_fresh_data`.
3. Insert the gate call between `reasoner_module.reason/1` and `CapabilityChecker.check/2` in `SnapshotSubscriber.run_pipeline`.
4. Update `Co2Rules` tests and OODA pipeline tests to reflect the new stage.

## Acceptance Criteria

- `Core.ActuatorGate` module exists and is tested independently.
- `Co2Rules` never returns `propose_no_action`; all tests still pass.
- `SnapshotSubscriber.run_pipeline` calls gate between reasoner and capability check.
- Golden traces for fan-already-on and fan-already-off cases still pass.
- `mix test` green.
