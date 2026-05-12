---
id: eig-d2o0
status: closed
deps: []
links: []
created: 2026-05-11T12:32:07Z
type: task
priority: 1
assignee: lispmeister
parent: eig-i05s
tags: [security, dashboard, trace]
---
# Broaden secret redaction across dashboard, traces, and error paths

Finish V1 secret redaction by auditing dashboard-visible assigns, trace or projection output, fault and status payloads, and common exception or error rendering so configured secrets and env-style secret names are never exposed.

## Acceptance Criteria

Focused tests prove HOME_ASSISTANT_TOKEN, EIGENFORGE_HMAC_SECRET, and values or names containing TOKEN, SECRET, PASSWORD, or KEY are redacted in dashboard assign data, trace JSON, fault or status output, and common error paths.

