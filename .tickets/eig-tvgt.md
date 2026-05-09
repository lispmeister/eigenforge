---
id: eig-tvgt
status: open
deps: []
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

Tampering a single byte in a committed golden trace causes verify_file/1 to fail. Changing `core_node_id`, `consensus_decision_id`, `consensus_status`, `quorum_ref`, local sequence continuity, or a catch-up event's append-only evidence shape also fails verification.

## Notes

**2026-05-09T14:00:32Z**

Aligned with revised spec: verification ticket now includes local SQLite consensus fields, node-local sequence continuity, and catch-up append-only evidence checks.
