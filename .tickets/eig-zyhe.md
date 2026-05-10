---
id: eig-zyhe
status: closed
deps: []
links: []
created: 2026-05-10T05:19:55Z
type: task
priority: 0
assignee: lispmeister
tags: [spec, v1]
---
# Apply SPEC-V1-FIXES-002 to Prototype V1 spec

Patch PROTOTYPE-V1-SPEC.md with the second fresh-eyes review: decision cadence, in-flight command guard, restart recovery, command lifecycle, after-action semantics, timestamp freshness, no-threshold persistence, secret redaction, canonical JSON edge cases, numeric representation, HMAC domain separation, retention, dashboard freshness semantics, and V1 fault-injection mini-slice.

## Acceptance Criteria

PROTOTYPE-V1-SPEC.md incorporates all 15 items from SPEC-V1-FIXES-002.md and git diff --check passes.


## Notes

**2026-05-10T05:24:08Z**

Applied all 15 SPEC-V1-FIXES-002 items to PROTOTYPE-V1-SPEC.md: decision cadence/dedupe, in-flight effect_key guard, restart recovery, command lifecycle, after-action status semantics, timestamp freshness, nominal coalescing, secret redaction, canonical JSON hardening, scaled sensor numerics, HMAC purpose labels, retention expectations, dashboard freshness semantics, V1 fault-injection mini-slice, and matching implementation tickets/notes.
