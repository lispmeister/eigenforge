---
id: eig-eudn
status: open
deps: [eig-hs04, eig-193d]
links: []
created: 2026-05-09T14:11:13Z
type: feature
priority: 2
assignee: lispmeister
tags: [v1-dashboard]
---
# Implement read-only LiveView dashboard

Implement Phoenix LiveView dashboard showing IO mode, connection status, latest sensor/fan state, reasoner outcome, policy decision, last command, after-action status, recent ledger events, raw IO fault/status events, and stale sensor alerts.

## Acceptance Criteria

Dashboard is read-only; it does not call Home Assistant, write SQLite ledgers, or issue commands; simulator mode is clearly indicated; displayed durable history comes from local projections/ledger.


## Notes

**2026-05-10T05:09:59Z**

2026-05-10 spec clarification update: dashboard should surface simulator mode, degraded/recovered connection status, stale sensor alert status, recent IO fault/status stream entries, and durable decision/action history from projections only.

**2026-05-10T05:23:51Z**

SPEC-V1-FIXES-002 applied: dashboard must display distinct freshness/status labels including not_yet_observed, pending_command, and degraded, and must not expose redacted secrets.
