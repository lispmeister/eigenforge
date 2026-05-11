---
id: eig-ag8j
status: open
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

