---
id: eig-defb
status: closed
deps: []
links: []
created: 2026-05-14T07:48:10Z
type: task
priority: 2
assignee: lispmeister
---
# Decide the delivery_receipt persistence boundary

This is a design-evaluation ticket, not an implementation ticket. Mailbox currently owns a signed manifest, a durable phase-tracked receipt store, restart recovery, and projection rebuild. That is a second persistence boundary with its own integrity checks. An alternative is to emit `delivery_receipt_recorded` as a core ledger event and drop the separate mailbox SQLite store.

This ticket is a design evaluation + spec recommendation, not a code change. Investigate: (1) what V2 multi-core delivery semantics require — does a two-store split give V2 cleaner cross-node receipt routing? (2) does collapsing require core's ledger writer to accept mailbox writes from a different process, and what does that mean for the single-writer invariant? (3) what happens to the signed receipt payload — does it become a payload inside a ledger_event envelope? Produce a written recommendation in the spec or a companion doc, then file a follow-up implementation ticket if collapsing is chosen.

## Acceptance Criteria

A written recommendation exists in §9 or a companion design note. The recommendation explicitly covers V2 implications. If collapsing is chosen, a follow-up implementation ticket is filed. If keeping two stores, §9 acknowledges mailbox is not a purely dumb channel manager and names its role honestly.


## Notes

**2026-05-14T07:57:04Z**

Spec updated: §9 CommandTransport section includes a Receipt store evaluation note describing the two options and noting the design question is open. Full evaluation and implementation ticket still pending.

**2026-05-15T13:26:36Z**

Resolved by PROTOTYPE-V1-SPEC.md update: V1 keeps delivery receipts in the mailbox-owned signed receipt store; no collapse in V1.
