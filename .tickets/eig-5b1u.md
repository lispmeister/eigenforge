---
id: eig-5b1u
status: closed
deps: [eig-c2fz, eig-9toe, eig-p9ms]
links: []
created: 2026-05-09T14:10:37Z
type: feature
priority: 1
assignee: lispmeister
tags: [next-slice]
---
# Load and verify signed device inventory

Implement loading config/devices.json and signature sidecar through generated DeviceInventory contract. Device inventory supplies explicit active room selection, room_id, sensor/entity mappings, actuator metadata, transport_security, and idempotency.

## Acceptance Criteria

Signed device inventory verifies in both home_assistant and simulator runtime modes; exactly one room must declare `active: true`; unsigned allowance applies only to static simulator snapshot fixtures, not device inventory. Missing transport_security warns and displays unknown; fan idempotency drives actuator-state gate tests.


## Notes

**2026-05-10T05:09:36Z**

2026-05-10 spec clarification update: signed device inventory loading must honor simulator unsigned boundary: device inventory remains signed in normal runtime; only simulator snapshot fixtures may be unsigned.
