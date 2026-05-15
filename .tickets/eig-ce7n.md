---
id: eig-ce7n
status: closed
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 1
assignee: lispmeister
---
# Load and verify signed capability grants at startup (§8)

The spec (§8) requires:

> "Capabilities are static signed grants loaded at startup. V1 grant revocation, delegation, and expiration are deferred."

`CapabilityChecker` (`capability_checker.ex`) hardcodes `@grant_id "cap-core-rule-stub-fan"` and always returns `result: "allow"` without reading or verifying `config/capabilities/core_rule_stub_fan.json`. This makes `deny_missing_capability` and `deny_invalid_capability` structurally unreachable, and means the signing/verification pipeline for capability grants (`mix eigenforge.capability.grant`) is untested at runtime.

Required changes:
1. Load the signed capability grant (and its `.sig` sidecar) at startup via `SignedConfig` (similar to how device inventory is loaded in `SignedConfig.load_device_inventory/1`).
2. `CapabilityChecker.check/2` receives (or looks up) the loaded grants for the requested subject/target/action/scope.
3. If a matching grant exists and its signature verifies: return `result: "allow"`, `grant_id: grant.grant_id`.
4. If no matching grant exists: return `result: "deny_missing_capability"`.
5. If a grant exists but signature is invalid: return `result: "deny_invalid_capability"`.
6. Startup (`Bootstrap.validate` or `RuntimeConfig.load`) must fail if no capability config is found in `home_assistant` mode (same as device inventory).
7. Add tests for all three result paths using test fixtures with signed and unsigned grants.

## Acceptance Criteria

- `CapabilityChecker.check/2` reads grants from loaded config, not from module attributes.
- All three result values are reachable and tested.
- Startup fails when required capability config is missing in `home_assistant` mode.
- `mix eigenforge.ledger.verify` still passes on traces that exercise the grant path.
- `mix test` green.
