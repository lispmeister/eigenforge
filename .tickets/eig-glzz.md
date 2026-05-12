---
id: eig-glzz
status: closed
deps: [eig-bqzy, eig-gu9r]
links: [eig-xs66, eig-l5tk, eig-5mvh]
created: 2026-05-09T14:11:40Z
type: feature
priority: 2
assignee: lispmeister
tags: [next-slice]
---
# Implement mailbox command delivery receipt checks

Implement mailbox delivery of command envelopes after finalized local ledger commit and attach immutable signed DeliveryReceipt metadata. IO must verify envelope signature, receipt signature, expiry, matching command/decision ids, committed decision reference, and fresh idempotency key before execution. Mailbox receipt-store phase metadata tracks `receipt_stored`, `publish_attempted`, and `io_accepted` separately from the signed receipt body.

## Acceptance Criteria

Mailbox never authorizes or mutates command payloads; command delivery happens only after local ledger commit; receipt phase updates never rewrite signed receipts; IO rejects expired, duplicate, invalid signature, mismatched receipt, and uncommitted command references.


## Notes

**2026-05-10T05:09:37Z**

2026-05-10 spec clarification update: V1 committed-decision verification trusts signed delivery receipt evidence from mailbox after core commit; IO does not read core SQLite. Receipt must match command/decision ids and carry non-empty signed ledger_sequence/ledger_event_hash.

**2026-05-10T05:23:51Z**

SPEC-V1-FIXES-002 applied: IO must maintain a local durable command execution store keyed by idempotency_key and reject execution if the store is unavailable or fails verification after restart.

**2026-05-10T05:37:39Z**

SPEC-V1-FIXES-003 applied: mailbox must persist signed delivery receipts and minimal routing metadata before publishing commands, verify/rebuild receipt projections on restart, and start degraded without publishing/redelivering commands if the receipt store is corrupt or unverifiable.
