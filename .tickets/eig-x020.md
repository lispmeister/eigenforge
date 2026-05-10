---
id: eig-x020
status: open
deps: [eig-q25o, eig-zohd, eig-glzz, eig-xtqn, eig-5906, eig-dhm1]
links: []
created: 2026-05-09T14:11:22Z
type: feature
priority: 2
assignee: lispmeister
tags: [next-slice]
---
# Add remaining simulator fixtures and acceptance paths

Add simulator fixtures and trace coverage for co2_low_fan_on, co2_nominal_fan_off, and co2_malformed, plus malformed/missing capability and persistence-failure paths from the spec.

## Acceptance Criteria

Golden trace or focused tests cover fan-off, nominal no-threshold with runtime coalescing rules, malformed CO2 fault/deny, missing or invalid capability deny, ledger persistence failure with no IO delivery, duplicate snapshot dedupe, duplicate in-flight effect_key suppression, command timeout, invalid signature/receipt cases, first startup without mailbox receipt manifest, mailbox crash after `receipt_stored`, mailbox crash after `publish_attempted`, HA observation with misleading source wall time but older receive ordering, and restart with pending command including wall-clock jump.


## Notes

**2026-05-10T05:09:48Z**

2026-05-10 spec clarification update: acceptance traces must assert deterministic trace ids/clocks, exact event cardinality, no_command/not_checked for nominal/already-in-state paths, and stale/malformed CO2 safety snapshot plus deny path.

**2026-05-10T05:37:39Z**

SPEC-V1-FIXES-003 applied: fault/acceptance tests should cover wrong-class HA entity mapping, old actuator observation replay, manual HA fan change during pending command, corrupt mailbox receipt store, corrupt projections with valid ledger rebuild, unsupported schema/ledger versions, and command_expired mapping to timed_out.
