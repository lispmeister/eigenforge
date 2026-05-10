---
id: eig-60h5
status: closed
deps: []
links: []
created: 2026-05-08T13:33:14Z
type: chore
priority: 1
assignee: lispmeister
tags: [next-slice]
---
# Restructure repo as Elixir umbrella with five apps

Spec §2 requires apps/eigenforge_contracts, apps/eigenforge_io, apps/eigenforge_core, apps/eigenforge_mailbox, apps/eigenforge_dashboard. Current codebase is a single flat app.

## Acceptance Criteria

mix test from umbrella root runs all current tests; module names migrated correctly.


## Notes

**2026-05-10T05:09:18Z**

2026-05-10 spec clarification update: umbrella migration must place canonical schemas at apps/eigenforge_contracts/priv/schemas; other apps consume generated modules/helpers from eigenforge_contracts rather than keeping private schema copies.

**2026-05-10T06:00:05Z**

Implemented umbrella scaffold with apps/eigenforge_contracts, apps/eigenforge_core, apps/eigenforge_io, apps/eigenforge_mailbox, and apps/eigenforge_dashboard. Moved contract helpers/generated modules and canonical schemas into eigenforge_contracts, moved trace runner/tasks/tests into eigenforge_core, added minimal application supervisors for all five apps, updated generator paths and formatter config. Verified mix compile --warnings-as-errors, mix test, mix run tools/smoke_contracts.exs, and git diff --check.
