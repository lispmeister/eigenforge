---
id: eig-xtqn
status: open
deps: [eig-cj5v]
links: []
created: 2026-05-09T14:11:31Z
type: feature
priority: 2
assignee: lispmeister
tags: [next-slice]
---
# Implement after-action timeout handling

Implement EIGENFORGE_AFTER_ACTION_TIMEOUT_MS handling so core records terminal durable after-action statuses: confirmed_changed, confirmed_already_in_state, adapter_rejected, adapter_failed, state_mismatch, or timed_out from live actuator/fault observations. command_sent_but_unconfirmed is a non-terminal projection/runtime lifecycle state only.

## Acceptance Criteria

After-action observer records core-authored terminal outcomes linked to command/idempotency key/effect_key; timeout defaults to 3000 ms; tests cover confirmed_changed, confirmed_already_in_state, timed_out, adapter rejection/failure, state mismatch, non-terminal pending projection state, and rejection of confirmation evidence whose IO-local receive ordering predates command delivery/acceptance.


## Notes

**2026-05-10T05:09:59Z**

2026-05-10 spec clarification update: after-action recording remains core-authored; IO publishes actuator state/faults and core records confirmed_changed/confirmed_already_in_state/adapter_rejected/adapter_failed/state_mismatch/timed_out based on observed streams. command_sent_but_unconfirmed is non-terminal projection/runtime state only.

**2026-05-10T05:37:28Z**

SPEC-V1-FIXES-003 applied: after-action confirmation must reject actuator observations older than command delivered_at and treat HA REST success only as service acceptance, never as confirmed_changed/confirmed_already_in_state.

**2026-05-10T05:55:05Z**

SPEC-V1-FIXES-004 supersedes the older delivered_at-only wording: after-action confirmation must use IO-local receive ordering (/) to prove post-delivery arrival; source wall timestamps are preserved for replay rejection but are not sufficient by themselves.

**2026-05-10T05:55:13Z**

Correction to previous note: SPEC-V1-FIXES-004 requires IO-local receive ordering using source_received_seq/source_received_monotonic_ms to prove post-delivery arrival; source wall timestamps are replay evidence only, not sufficient confirmation ordering.
