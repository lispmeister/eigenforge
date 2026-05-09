---
id: eig-o1bf
status: open
deps: []
links: []
created: 2026-05-08T13:32:45Z
type: chore
priority: 2
assignee: lispmeister
tags: [code-quality]
---
# Read HMAC secret from config/env in Trace runner

lib/eigenforge/trace.ex:16 hardcodes @secret. The spec requires EIGENFORGE_HMAC_SECRET. Replace with Application.fetch_env!(:eigenforge, :hmac_secret) and set a test default in config/test.exs.

## Acceptance Criteria

Secret no longer hardcoded; golden traces still verify; EIGENFORGE_HMAC_SECRET flows through config/runtime.exs and signs local SQLite ledger events, command envelopes, receipts, and catch-up evidence consistently.

## Notes

**2026-05-09T14:00:32Z**

Aligned with revised spec: HMAC secret must sign local SQLite ledger events, command envelopes, receipts, and catch-up evidence consistently.
