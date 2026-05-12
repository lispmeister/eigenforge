---
id: eig-o4vn
status: closed
deps: []
links: []
created: 2026-05-12T08:24:27Z
type: bug
priority: 1
assignee: lispmeister
tags: [io, home-assistant, reconnect]
---
# Align Home Assistant reconnect lifecycle with spec status vocabulary

The Home Assistant client emits recovered on successful connect and resets the reconnect attempt counter immediately. The v1 spec uses connection_up as the stable connection event and resets the attempt counter only after a successful connection stays up long enough to publish connection_up. Align the implementation and status stream vocabulary with the spec.

## Acceptance Criteria

Successful reconnection publishes connection_up rather than recovered; reconnect_attempt resets only after a stable connection has published connection_up; degraded/reconnecting states remain visible; tests cover the stable-connection reset behavior and the emitted fault/status names.

