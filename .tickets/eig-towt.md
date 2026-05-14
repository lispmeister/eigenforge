---
id: eig-towt
status: closed
deps: []
links: []
created: 2026-05-14T07:44:22Z
type: task
priority: 2
assignee: lispmeister
---
# Spec §2: add a numbered V1 Invariants section

V1 invariants are scattered across §6, §7, §9, §10, §11: no command without committed decision-chain ledger, no second stale-deny per (snapshot_id, correlation_id), no equivalent command while in-flight, ledger sequence contiguous and node-local, IO executes at most once per idempotency_key, only core authors after-action terminals, etc. Pulling them into one numbered list gives mix eigenforge.ledger.verify and eigenforge.trace.verify a single audit target and lets failure messages cite invariant IDs.

Proposed change: add §2.x 'V1 Invariants' with ~10-15 numbered invariants (INV-01, INV-02, …), each with a one-line statement and a back-reference to the spec section that derives it. mix eigenforge.ledger.verify and eigenforge.trace.verify may cite invariant IDs in failure messages in a follow-up ticket.

## Acceptance Criteria

New §2.x V1 Invariants section exists with at least 10 numbered invariants. Each invariant is one sentence and includes a section cross-reference. The invariant IDs are stable and suitable for use in verifier failure messages.

