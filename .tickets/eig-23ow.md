---
id: eig-23ow
status: closed
deps: [eig-l5tk, eig-cj5v]
links: []
created: 2026-05-10T05:07:09Z
type: feature
priority: 2
assignee: lispmeister
parent: eig-rql0
tags: [v1-io, home-assistant]
---
# Implement Home Assistant reconnect and degraded startup behavior

Implement clarified Home Assistant runtime behavior: fail fast for missing/invalid required static config, but start degraded when HA is unreachable after valid config loads; publish connection_up/connection_down/reconnecting/degraded/recovered fault/status events; retry with deterministic capped exponential backoff using `delay_ms = min(5000 * 2 ^ (attempt - 1), EIGENFORGE_HA_RECONNECT_MAX_MS)`.

## Acceptance Criteria

Tests or simulator-controlled adapter checks cover fail-fast config errors separately from recoverable HA connectivity failures; backoff delay, cap, reset behavior, and test-disabled jitter; dashboard/projections can observe degraded and recovered connection status.
