---
id: eig-fydk
status: closed
deps: []
links: []
created: 2026-05-10T05:44:17Z
type: task
priority: 0
assignee: lispmeister
tags: [spec, v1]
---
# Apply SPEC-V1-FIXES-004 to Prototype V1 spec

Patch PROTOTYPE-V1-SPEC.md with SPEC-V1-FIXES-004 clarifications: mailbox crash gap, receipt-store initialization, monotonic restart semantics, HA observation ordering, active room flag, HA dynamic entity validation, payload authority categories, delivery receipt signature shape, effect_epoch observation ids, and deterministic reconnect backoff.


## Notes

**2026-05-10T05:47:44Z**

Applied SPEC-V1-FIXES-004 to PROTOTYPE-V1-SPEC.md: clarified mailbox receipt-store initialization and delivery phases, monotonic-vs-restart time semantics, HA static/dynamic entity validation, local receive ordering for after-action, explicit active room flag, payload authority classes, immutable delivery receipt signature shape, effect_epoch observation ids, deterministic reconnect backoff, and added corresponding fault-injection cases. Verified git diff --check and tk dep cycle.
