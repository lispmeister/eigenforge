---
id: eig-wmk7
status: closed
deps: []
links: []
created: 2026-05-12T09:11:23Z
type: bug
priority: 1
assignee: lispmeister
tags: [v1, spec, tests, io]
---
# Add HA client tests for invalid command signature and receipt mismatches

Spec requires fault-injection coverage for invalid command signatures and mismatched delivery receipt command/decision IDs. Verification branches exist in HomeAssistantClient.verify_delivery/3 but are not directly exercised by tests.

## Acceptance Criteria

1. Add tests in apps/eigenforge_io/test/eigenforge/io/home_assistant_client_test.exs for invalid command signature and invalid delivery receipt signature. 2. Add tests for receipt command_id mismatch and decision_event_id mismatch. 3. Assert command is not dispatched to transport and receipt phase remains non-io_accepted. 4. Full mix test passes.

