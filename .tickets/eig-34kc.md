---
id: eig-34kc
status: closed
deps: []
links: []
created: 2026-05-12T09:11:23Z
type: bug
priority: 1
assignee: lispmeister
tags: [v1, spec, tests, core, restart, timing]
---
# Add core restart-recovery test for wall-clock jump with pending command deadline

Spec requires restart behavior when wall clock jumps while pending command has persisted UTC expiry/after-action deadline. IO monotonic-expiry tests exist, but explicit core pending-command restart recovery coverage for this case is missing.

## Acceptance Criteria

1. Add test in apps/eigenforge_core/test/eigenforge/core/ooda_pipeline_test.exs that persists a pending command, simulates restart with shifted wall-clock baseline, and validates timeout/confirmation behavior derives from persisted UTC deadline correctly. 2. Assert no duplicate command issuance during recovery. 3. Assert durable terminal after_action_recorded status is produced as expected. 4. Full mix test passes.

