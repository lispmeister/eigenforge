---
id: eig-5u7f
status: open
deps: [eig-pp46]
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

Fresh local SQLite core ledger: genesis succeeds with the configured `core_node_id`, verify passes. Manual row tamper: verify fails on the tampered row. Verify also checks contiguous node-local sequence numbers, previous-hash links, `core_node_id`, consensus status/reference shape, and that catch-up events append locally rather than reusing foreign sequence numbers or foreign event hashes as local event hashes.

## Notes

**2026-05-09T14:00:19Z**

Aligned with revised append-only ledger spec: verify must check local core identity, contiguous node-local sequence, consensus fields, and append-only catch-up evidence shape.
