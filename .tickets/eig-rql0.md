---
id: eig-rql0
status: open
deps: [eig-p9ms, eig-q25o, eig-nu0t, eig-23ow, eig-wyul, eig-0ttx, eig-193d, eig-a8hg, eig-glzz, eig-xtqn, eig-i05s, eig-5906, eig-zohd, eig-x020, eig-jtma, eig-5u7f, eig-dhm1, eig-wdwi, eig-tvgt, eig-f5tl, eig-5mvh, eig-7vfe, eig-zp2l, eig-j5tr]
links: []
created: 2026-05-10T05:06:35Z
type: epic
priority: 1
assignee: lispmeister
tags: [v1]
---
# Implement remaining Prototype V1 spec

Umbrella tracker for the remaining V1 implementation work after SPEC-V1-FIXES-001 and the 2026-05-10 spec clarification. Existing implementation tickets remain authoritative for their areas; this epic groups the missing follow-up tickets and clarified dependencies.

## Acceptance Criteria

All V1 executable requirements in PROTOTYPE-V1-SPEC.md are covered by open or closed tk tickets with dependencies that preserve the simulator-first implementation order.


## Notes

**2026-05-10T05:11:27Z**

2026-05-10 ticket prep: updated existing slice-one tickets with clarified V1 spec notes and added missing implementation tickets for schema alignment, deterministic trace identity/time, snapshot hash/freshness, control-path cardinality, idempotency, command event references, capability grant lookup, sample signed config, HA degraded reconnect behavior, connection transition persistence, non-fan stubs, and HTML visualization refresh. Dependency graph checked with tk dep cycle.

**2026-05-10T05:28:47Z**

2026-05-10 alignment pass: refreshed ticket bodies and dependencies against current PROTOTYPE-V1-SPEC.md after SPEC-V1-FIXES-002. Removed stale unsigned simulator config language, made command_sent_but_unconfirmed non-terminal, removed V2 catch-up from V1 verification acceptance, aligned ledger consensus-field requiredness, added effect_key/scaled sensor/canonical JSON/redaction/dashboard/fault-injection coverage to relevant tickets, and rechecked tk dep cycle.

**2026-05-10T05:39:49Z**

Aligned remaining V1 implementation epic with SPEC-V1-FIXES-003: added/linked tickets for HA manual-state observation semantics, mailbox receipt store recovery, schema/fixture version validation, and monotonic runtime clocks.

**2026-05-10T05:55:05Z**

2026-05-10 SPEC-V1-FIXES-004 ticket alignment: updated V1 tickets for receipt-store manifest and delivery phases, immutable receipt signatures, monotonic-vs-restart timing, HA static/dynamic validation, deterministic reconnect backoff, source observation/receive ordering fields, active room selection, payload authority classes, and new fault-injection coverage. Verified tk dep cycle and git diff --check.

**2026-05-10T11:27:29Z**

2026-05-10 final coverage check for /goal: reviewed PROTOTYPE-V1-SPEC.md against existing tk graph, confirmed v1 executable scope is covered by eig-rql0 and its direct/indirect blockers; no duplicate tickets created. Verified tk dep cycle and tk ready.
