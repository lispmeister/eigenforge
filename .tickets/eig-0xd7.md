---
id: eig-0xd7
status: closed
deps: []
links: []
created: 2026-05-12T09:11:23Z
type: bug
priority: 2
assignee: lispmeister
tags: [v1, spec, tests, core, io]
---
# Add test for unwritable IO fault-status log path behavior

Spec fault-injection list includes unwritable IO debug log path. IoFaultStatus.append_debug_log/2 has a failure path but no explicit test asserting behavior when log path cannot be written.

## Acceptance Criteria

1. Add test in apps/eigenforge_core/test/eigenforge/core/io_fault_status_test.exs for unwritable log path. 2. Assert IoFaultStatus.record/2 returns error and does not emit invalid durable state transitions. 3. Ensure redaction/persistence behavior remains unchanged in normal path tests. 4. Full mix test passes.

