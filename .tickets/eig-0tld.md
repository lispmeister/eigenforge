---
id: eig-0tld
status: closed
deps: []
links: []
created: 2026-05-10T04:57:16Z
type: task
priority: 0
assignee: lispmeister
---
# Clarify Prototype V1 spec ambiguities

Apply SPEC-V1-FIXES-001 plus fresh review findings to PROTOTYPE-V1-SPEC.md before continuing v1 implementation ticket prep.

## Acceptance Criteria

PROTOTYPE-V1-SPEC.md resolves stale flow, event cardinality, idempotency, schema ownership, timestamp format, startup/mode behavior, schema/prose drift, deterministic trace IDs/clocks, snapshot hash semantics, ledger field requirements, and V1/V2 boundary wording.


## Notes

**2026-05-10T05:01:14Z**

Updated PROTOTYPE-V1-SPEC.md to resolve V1 ambiguity before implementation ticket prep: schema ownership, startup matrix, timestamp format, simulator unsigned boundaries, malformed/stale flow, reasoner/gate ownership, policy results, idempotency derivation, mailbox receipt trust, ledger event cardinality, consensus field applicability, deterministic trace IDs/clocks, and V1/V2 scope boundary.
