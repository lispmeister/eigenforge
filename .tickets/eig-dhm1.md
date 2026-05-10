---
id: eig-dhm1
status: closed
deps: [eig-p9ms]
links: []
created: 2026-05-10T05:23:08Z
type: task
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [contracts, io, next-slice]
---
# Implement V1 scaled sensor numeric fields

Replace signed humidity_percent and temperature_c fields with humidity_basis_points and temperature_millicelsius in schemas, generated modules, simulator fixtures, normalizer, projections, dashboard display conversion, and golden traces.

## Acceptance Criteria

No signed normalized snapshot or golden trace uses floating point humidity/temperature; display layers render scaled integer values correctly.

