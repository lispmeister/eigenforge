---
id: eig-3za6
status: closed
deps: []
links: []
created: 2026-05-10T05:34:02Z
type: task
priority: 0
assignee: lispmeister
tags: [spec, v1]
---
# Apply SPEC-V1-FIXES-003 to Prototype V1 spec

Patch PROTOTYPE-V1-SPEC.md with the third fresh-eyes review: manual HA state boundaries, fail-safe posture, HA REST semantics, actuator observation ordering, monotonic clocks, corrupted local store behavior, mailbox receipt persistence, command expiry after-action mapping, one-room config validation, schema/ledger version migration stance, HA entity validation, fan-off safety asymmetry, fixture schema/version, operator audit promotion, and no autonomous recovery command invariant.

## Acceptance Criteria

PROTOTYPE-V1-SPEC.md incorporates SPEC-V1-FIXES-003.md and git diff --check passes.


## Notes

**2026-05-10T05:39:49Z**

Applied SPEC-V1-FIXES-003 to PROTOTYPE-V1-SPEC.md. Added startup/recovery invariants, HA entity and observation semantics, simulator fixture versioning, strict schema-version handling, monotonic runtime duration rules, one-room inventory validation, mailbox receipt-store recovery, command-expiry mapping, and operator-audit promotion limits. Updated implementation tickets/dependencies to match.
