---
id: eig-l5tk
status: closed
deps: [eig-c2fz, eig-5b1u]
links: [eig-xs66, eig-glzz, eig-5mvh]
created: 2026-05-09T14:10:46Z
type: feature
priority: 2
assignee: lispmeister
tags: [v1-io]
---
# Implement Home Assistant IO adapter

Implement Home Assistant mode: WebSocket state ingest for configured CO2/humidity/temperature/fan entities and REST switch.turn_on/switch.turn_off execution for the fan actuator. Include degraded startup, deterministic capped exponential reconnect backoff, static entity-id config validation, dynamic post-connect entity validation, source receive ordering fields, and manual/external fan observations as live observations rather than commands.

## Acceptance Criteria

Home Assistant mode normalizes state into snapshots with `source_observation_ids`, `source_received_seq`, and `source_received_monotonic_ms`; REST fan commands use configured entity id; unreachable HA starts degraded and retries with the specified capped exponential backoff; missing required static config fails startup; dynamic wrong/missing entities enter degraded/no-physical-control state; REST success is not after-action confirmation; no HA connection is attempted in simulator mode.


## Notes

**2026-05-10T05:09:58Z**

2026-05-10 spec clarification update: HA adapter work must separate fail-fast config validation from recoverable HA connectivity failures, publish degraded/reconnect/recovered status, and use switch.turn_on/switch.turn_off for the fan entity.

**2026-05-10T05:37:28Z**

SPEC-V1-FIXES-003 applied: HA adapter must validate sensor/switch-compatible entity classes, treat REST service success as accepted-not-confirmed, preserve source timestamps on replayed HA events, and surface manual/external HA fan changes as observations rather than Eigenforge commands.
