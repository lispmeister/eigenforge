---
id: eig-60h5
status: open
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

