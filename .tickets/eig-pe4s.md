---
id: eig-pe4s
status: closed
deps: [eig-ag1x, eig-ce7n]
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 1
assignee: lispmeister
---
# PolicyEngine is missing 6 of 9 spec-required decision types (§8)

The spec (§8) defines nine policy decision results. The schema (`policy_decision.schema.json`) correctly enumerates all nine. `PolicyEngine` (`policy_engine.ex`) implements only three: `deny_stale_snapshot`, `allow`, and `no_command`. Six are unreachable from the engine:

- `deny_missing_capability` — when `CapabilityChecker` returns `deny_missing_capability`
- `deny_invalid_capability` — when `CapabilityChecker` returns `deny_invalid_capability`
- `deny_unknown_non_idempotent_actuator_state` — when gate blocks a non-idempotent actuator with unknown state (requires eig-ag1x)
- `deny_expired_command` — when a command arrives at the policy stage but `expires_at` has passed
- `deny_unsupported_action` — when the requested action is not in the device's `actions` list
- `noop_stub` — for light/laser/beeper stub targets (currently returned from IO actuator stubs, not policy)

Required changes:
1. `PolicyEngine.decide/3` must inspect `CapabilityCheck.result` and return `deny_missing_capability` or `deny_invalid_capability` when capability was denied.
2. Add a `deny_unknown_non_idempotent_actuator_state` branch triggered by the gate outcome from eig-ag1x.
3. Add `deny_expired_command` check using command expiry from the snapshot or reasoner outcome context.
4. Add `deny_unsupported_action` for unrecognised action values.
5. Map light/laser/beeper stub targets to `noop_stub` at policy stage (or confirm they remain IO-only and document the decision).
6. Add a test for each of the six new branches.

## Acceptance Criteria

- All nine spec decision types are reachable from `PolicyEngine.decide/3`.
- Each branch is covered by a unit test.
- Golden traces that exercise deny paths still pass.
- `mix test` green.
