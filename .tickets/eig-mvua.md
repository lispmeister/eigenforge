---
id: eig-mvua
status: closed
deps: []
links: []
created: 2026-05-14T07:45:01Z
type: task
priority: 4
assignee: lispmeister
---
# Duplicate of eig-lm2z: add mix eigenforge.ledger.migrate no-op stub (§4)

§4 says 'Forward/backward migrations require an explicit later migration tool.' No tool exists and there is no enforcement that prevents workarounds that would silently accept future schema drift. Stubbing the interface now reserves it and makes accidental drift fail loudly.

Proposed change: add mix eigenforge.ledger.migrate --from N --to M that in V1: asserts every ledger payload's schema_version == 1; exits 0 when --from 1 --to 1 is passed; exits non-zero with 'no V1→Vn migration defined' when any other range is passed. Reference the task in §4.

## Acceptance Criteria

mix eigenforge.ledger.migrate task exists. §4 references it. Integration test covers --from 1 --to 1 (exit 0) and --from 1 --to 2 (exit non-zero with clear message).


## Notes

**2026-05-14T07:57:04Z**

Spec updated: §4 now references mix eigenforge.ledger.migrate and its V1 behavior. Mix task still needs to be implemented.
