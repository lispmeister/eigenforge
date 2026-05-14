---
id: eig-defb
status: open
deps: []
links: []
created: 2026-05-14T07:48:10Z
type: task
priority: 2
assignee: lispmeister
---
# Spec §9/§11: evaluate collapsing mailbox delivery_receipt into a core ledger event

Mailbox is described as a 'dumb channel manager' but owns a signed manifest, durable phase-tracked receipt store, restart recovery, and projection rebuild. That is a second persistence boundary with its own integrity checks. An alternative: mailbox emits delivery_receipt_recorded as a ledger event through the core ledger writer, dropping the separate mailbox SQLite store. One persistence boundary; mailbox becomes truly mechanical.

This ticket is a design evaluation + spec recommendation, not a code change. Investigate: (1) what V2 multi-core delivery semantics require — does a two-store split give V2 cleaner cross-node receipt routing? (2) does collapsing require core's ledger writer to accept mailbox writes from a different process, and what does that mean for the single-writer invariant? (3) what happens to the signed receipt payload — does it become a payload inside a ledger_event envelope? Produce a written recommendation in the spec or a companion doc, then file a follow-up implementation ticket if collapsing is chosen.

## Acceptance Criteria

Written recommendation exists in §9 or a companion design note. Recommendation explicitly covers V2 implications. If collapsing is chosen, a follow-up implementation ticket is filed. If keeping two stores, §9 acknowledges mailbox is not dumb and renames its role honestly.


## Notes

**2026-05-14T07:57:04Z**

Spec updated: §9 CommandTransport section includes a Receipt store evaluation note describing the two options and noting the design question is open. Full evaluation and implementation ticket still pending.
