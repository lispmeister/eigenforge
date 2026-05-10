---
id: eig-tvgt
status: closed
deps: [eig-777e, eig-5906]
links: []
created: 2026-05-08T13:32:45Z
type: chore
priority: 2
assignee: lispmeister
tags: [code-quality]
---
# Make Trace.verify_file/1 re-compute hash chain and HMAC signatures

trace.ex verify must not trust the cached boolean verification map in the golden trace file. It must walk `ledger_events`, recompute payload/event hashes and HMAC signatures, verify previous-hash links, and enforce the local SQLite consensus fields added by the revised spec.

## Acceptance Criteria

Tampering a single byte in a committed golden trace causes verify_file/1 to fail. Changing `core_node_id`, V1 `consensus_decision_id`/`consensus_status` applicability, `quorum_ref={}`, local sequence continuity, command event references, deterministic ids/clocks, effect_key/idempotency references, or purpose-labeled signatures also fails verification. V2 catch-up evidence checks are deferred unless a later ticket promotes them into V1 scope.

## Notes

**2026-05-09T14:00:32Z**

Aligned with revised spec: verification ticket now includes local SQLite consensus fields, node-local sequence continuity, and catch-up append-only evidence checks.

**2026-05-10T05:09:48Z**

2026-05-10 spec clarification update: verifier must compare deterministic golden trace ids/clocks, exact control-path event cardinality, command event references, and V1-only scope; V2 quorum/catch-up checks should not block V1 unless explicitly implemented later.
