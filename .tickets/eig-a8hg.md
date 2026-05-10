---
id: eig-a8hg
status: closed
deps: [eig-60h5, eig-p9ms]
links: []
created: 2026-05-08T13:33:14Z
type: feature
priority: 2
assignee: lispmeister
tags: [next-slice]
---
# Add JSON Schema validation against priv/schemas in Contracts

Spec §4: schemas exist in priv/schemas but contract validation is structural-only. Add JSON Schema validation and reject contract payloads whose schema_id/schema_version do not match a known local schema for their authority class.

## Acceptance Criteria

Contracts with unknown schema_id/schema_version, duplicate keys, noncanonical timestamps, unexpected nullable fields, stale enum values, authority-class mismatches, or schema/prose field drift are rejected at construction or verification; golden traces still pass after regeneration.


## Notes

**2026-05-10T05:09:37Z**

2026-05-10 spec clarification update: schema validation must reject schema/prose drift for field names, enum values, requiredness, schema_id/schema_version, and canonical timestamp format after schemas are aligned.
