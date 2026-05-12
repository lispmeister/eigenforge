---
id: eig-ag8j
status: closed
deps: []
links: []
created: 2026-05-11T12:37:01Z
type: chore
priority: 3
assignee: lispmeister
tags: [v2, deps, phoenix]
---
# Investigate and reduce Phoenix dependency compiler warnings for V2

Track the dependency-side compiler warnings currently emitted from Phoenix during mix compile. Determine whether they can be eliminated by upgrading Phoenix or related dependencies, adjusting pinned versions, or contributing a local or upstream fix without destabilizing Eigenforge.

## Acceptance Criteria

V2 investigation documents the current warnings, identifies whether they are resolved by dependency upgrades or require upstream changes, and either removes the warnings from normal compile output or records a clear rationale for leaving them in place.


## Notes

**2026-05-12T08:58:50Z**

2026-05-12 investigation pass: current mix compile output is clean after the V1 bug fixes; no Phoenix dependency compiler warnings were observed in the current repo state, so there is nothing further to reduce in V2 warning output at this time.
