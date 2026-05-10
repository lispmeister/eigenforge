---
id: eig-o1bf
status: closed
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

Secret no longer hardcoded; golden traces still verify; EIGENFORGE_HMAC_SECRET flows through config/runtime.exs and signs local SQLite ledger events, command envelopes, receipts, config/capability sidecars, and other V1 signed artifacts with purpose/domain labels.

## Notes

**2026-05-09T14:00:32Z**

Aligned with revised spec: HMAC secret must sign local SQLite ledger events, command envelopes, receipts, config/capability sidecars, and other V1 signed artifacts consistently. V2 catch-up evidence is guidance, not this ticket's V1 scope.

**2026-05-10T05:10:08Z**

2026-05-10 spec clarification update: HMAC secret is required in both home_assistant and simulator modes for signed generated decisions, command envelopes, receipts, and ledger events; unsigned allowance applies only to simulator snapshot inputs.
