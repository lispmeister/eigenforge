---
id: eig-gu9r
status: open
deps: [eig-777e, eig-q25o, eig-5906]
links: []
created: 2026-05-10T05:07:09Z
type: feature
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [next-slice, mailbox, core]
---
# Implement V1 command idempotency key derivation

Implement the clarified decision retry idempotency_key algorithm: canonical JSON over format_version, core_node_id, room_id, subject, target, action, scope, requested_state, snapshot_id, snapshot_hash, reasoner_outcome_id, policy_decision_id, and consensus_decision_id; SHA-256 lowercase hex with idem:v1: prefix; exclude issued_at, expires_at, delivery metadata, ledger sequence, and event_hash. Physical-effect suppression is handled separately by effect_key in the command lifecycle ticket.

## Acceptance Criteria

Core, mailbox, IO, and trace tests agree on idempotency keys; retries of the same finalized decision keep the same key; distinct consensus_decision_id values produce distinct keys; IO rejects duplicate executed idempotency keys using its durable command execution store.
