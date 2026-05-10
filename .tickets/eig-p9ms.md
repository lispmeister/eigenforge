---
id: eig-p9ms
status: closed
deps: [eig-60h5, eig-7znw]
links: []
created: 2026-05-10T05:06:54Z
type: task
priority: 0
assignee: lispmeister
parent: eig-rql0
tags: [next-slice, contracts]
---
# Align schemas and generated contracts with clarified V1 spec

Update JSON Schemas and generated contract modules to match PROTOTYPE-V1-SPEC.md after the 2026-05-10 clarifications: IoFaultStatusEvent uses fault_type enum, PolicyDecision includes no_command/not_checked and excludes deny_rate_limited, LedgerEvent constrains fixed V1 event_type values and permits nullable consensus fields for non-decision events, ReasonerOutcome includes reasoner_outcome_id, timestamps use canonical millisecond UTC strings, normalized snapshots include source observation/receive ordering fields, delivery receipts have immutable signed bodies with no separate payload_hash, and schemas live under apps/eigenforge_contracts/priv/schemas after umbrella migration.

## Acceptance Criteria

Contract schemas, generated modules, fixtures, and golden traces use the same field names/enums/requiredness as the clarified spec; payload authority classes are represented in validation/signing helpers; schema/prose drift checks are documented or tested.


## Notes

**2026-05-10T05:23:41Z**

SPEC-V1-FIXES-002 applied: schema alignment must also cover effect_key fields, not_yet_observed source status, scaled humidity_basis_points and temperature_millicelsius, tightened canonical JSON profile, and HMAC purpose labels.

**2026-05-10T06:06:41Z**

Aligned V1 schemas/generated contracts with PROTOTYPE-V1-SPEC.md: IoFaultStatusEvent now uses fault_type enum; NormalizedSnapshot uses humidity_basis_points, temperature_millicelsius, source_observation_ids, source_received_seq, and source_received_monotonic_ms; CommandEnvelope and AfterActionEvent include effect_key; AfterActionEvent terminal statuses exclude command_sent_but_unconfirmed; PolicyDecision enums include no_command/not_checked and exclude deny_rate_limited; LedgerEvent has fixed V1 event_type enum and nullable consensus fields for non-decision events; DeviceInventory rooms require active. Regenerated contracts, simulator fixtures, smoke script, and golden traces. Verified mix test, mix compile --warnings-as-errors, mix run tools/smoke_contracts.exs, git diff --check, and tk dep cycle.
