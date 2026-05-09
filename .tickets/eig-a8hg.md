---
id: eig-a8hg
status: open
deps: [eig-60h5]
links: []
created: 2026-05-08T13:33:14Z
type: feature
priority: 2
assignee: lispmeister
tags: [next-slice]
---
# Add JSON Schema validation against priv/schemas in Contracts

Spec §4: schemas exist in priv/schemas but contract validation is structural-only. Add ex_json_schema and reject signed payloads whose schema_id/schema_version don't match a known local schema.

## Acceptance Criteria

Contracts with unknown schema_id are rejected at construction; golden traces still pass.

