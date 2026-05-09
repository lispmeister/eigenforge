---
id: eig-5sjl
status: closed
deps: []
links: []
created: 2026-05-09T13:55:34Z
type: task
priority: 1
assignee: lispmeister
---
# Tighten append-only command ledger spec

Clarify PROTOTYPE-V1-SPEC.md so every core node ledger remains strictly append-only, including catch-up, projection updates, SQLite write rules, and V2 network split repair.

## Acceptance Criteria

Spec explicitly forbids ledger row updates/deletes/replacements/resequencing; catch-up appends local evidence events rather than importing/splicing foreign ledger rows; projections are clearly separate mutable read models; verification covers append-only invariants.


## Notes

**2026-05-09T13:57:36Z**

Tightened PROTOTYPE-V1-SPEC.md append-only command ledger rules: catch-up appends local evidence events only, forbids copying/splicing foreign rows or reusing foreign sequence/hash as local identity, clarifies projection mutability is separate from ledger immutability, and forbids replace/update/backfill write paths.
