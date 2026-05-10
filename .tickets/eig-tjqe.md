---
id: eig-tjqe
status: closed
deps: []
links: []
created: 2026-05-08T13:32:45Z
type: chore
priority: 2
assignee: lispmeister
tags: [code-quality]
---
# Replace String.to_atom with String.to_existing_atom in Contracts.normalize_keys

lib/eigenforge/contracts.ex:171 calls String.to_atom/1 on decoded JSON keys. In Home Assistant mode this will run on network data, risking atom-table exhaustion.

## Acceptance Criteria

normalize_keys/1 uses String.to_existing_atom/1 and rejects unknown string keys safely; tests cover an unknown-key fixture.


## Notes

**2026-05-10T05:10:08Z**

2026-05-10 spec clarification update: normalization must not create atoms for untrusted schema or IO fields; clarified schema validation makes exact existing field names/enums important.
