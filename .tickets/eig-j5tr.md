---
id: eig-j5tr
status: closed
deps: [eig-p9ms, eig-a8hg, eig-193d]
links: []
created: 2026-05-10T05:36:54Z
type: task
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [contracts, trace, config]
---
# Implement V1 schema version and simulator fixture validation

Enforce V1 no-runtime-migration stance and payload authority classes: fail startup on unsupported schema_id/schema_version/format_version in ledger payloads, runtime config, sidecars, simulator fixtures, or generated contracts. Add fixture_schema_id, fixture_schema_version, and scenario id validation for unsigned simulator snapshot fixtures, including intentional malformed fixture declarations.

## Acceptance Criteria

Tests reject unsupported schema/format versions at startup and trace load; validation distinguishes unsigned contract fixtures, detached-signed config/grants, and ledger-contained durable payloads; simulator fixtures require fixture schema/version/scenario id; malformed fixture tests must declare the field or omission being exercised.
