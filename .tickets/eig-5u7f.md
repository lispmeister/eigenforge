---
id: eig-5u7f
status: closed
deps: [eig-pp46, eig-5906]
links: []
created: 2026-05-08T13:33:14Z
type: feature
priority: 1
assignee: lispmeister
tags: [next-slice]
---
# Implement mix eigenforge.ledger.genesis and mix eigenforge.ledger.verify

Genesis task: create sequence-1 ledger_genesis event with previous_event_hash=eigenforge-ledger-genesis-v1. Verify task: walk ledger in sequence order, recompute hashes/signatures, report first break.

## Acceptance Criteria

Fresh local SQLite core ledger: genesis succeeds with the configured `core_node_id`, verify passes. Manual row tamper: verify fails on the tampered row. Verify also checks contiguous node-local sequence numbers, previous-hash links, `core_node_id`, V1 consensus status/reference applicability, canonical timestamp format, purpose-labeled HMAC signatures, and fixed V1 event types. V2 catch-up evidence checks are deferred.

## Notes

**2026-05-09T14:00:19Z**

Aligned with revised append-only ledger spec: verify must check local core identity, contiguous node-local sequence, V1 consensus fields, and append-only hash-chain integrity. V2 catch-up evidence shape is not part of this V1 ticket.

**2026-05-10T05:09:18Z**

2026-05-10 spec clarification update: V1 ledger verify should enforce clarified V1 event types, canonical millisecond UTC timestamps, nullable consensus fields for non-decision events, and node-local append-only hash/signature checks. V2 catch-up verification is guidance, not a V1 blocker.
