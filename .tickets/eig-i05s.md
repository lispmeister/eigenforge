---
id: eig-i05s
status: open
deps: [eig-eudn, eig-cj5v, eig-5906]
links: []
created: 2026-05-10T05:23:08Z
type: task
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [security, v1]
---
# Implement V1 secret redaction

Apply V1 secret redaction rules across golden traces, debug logs, IO fault logs, dashboard output, test failures, and exceptions. Redact HOME_ASSISTANT_TOKEN, EIGENFORGE_HMAC_SECRET, and variables containing TOKEN, SECRET, PASSWORD, or KEY as [REDACTED].

## Acceptance Criteria

Focused tests prove secrets do not appear in trace JSON, log messages, fault/status events, dashboard assign data, or common error paths.

