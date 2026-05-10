---
id: eig-tzyb
status: closed
deps: [eig-p9ms]
links: []
created: 2026-05-10T05:06:54Z
type: feature
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [next-slice, io, contracts]
---
# Implement normalized snapshot hash sequence and freshness semantics

Implement clarified NormalizedSnapshot behavior: snapshot_seq scoped per IO source and room, snapshot_hash over canonical snapshot body excluding itself/signature fields, source_observation_ids/source_received_seq/source_received_monotonic_ms captured for contributing sources, top-level freshness represents CO2 control freshness, observe-only humidity/temperature status does not block fan action, and malformed representable CO2 becomes a safety snapshot plus fault/status event.

## Acceptance Criteria

Tests cover snapshot hash determinism including receive-order fields, sequence scoping, fresh CO2 with stale observe-only values, stale/malformed/missing CO2 deny input, fan source observation ids for effect_epoch, and malformed fan state behavior for idempotent vs non-idempotent actuators.


## Notes

**2026-05-10T05:23:51Z**

SPEC-V1-FIXES-002 applied: normalized snapshot work must implement source timestamp freshness math, future timestamp skew handling, not_yet_observed, snapshot dedupe/cadence inputs, and scaled numeric sensor fields.

**2026-05-10T05:37:39Z**

SPEC-V1-FIXES-003 applied: source freshness age should use monotonic timestamps captured with source events/snapshot observation, while signed records keep canonical wall-clock UTC strings.
