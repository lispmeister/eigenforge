---
id: eig-cj5v
status: closed
deps: []
links: []
created: 2026-05-09T14:10:56Z
type: feature
priority: 2
assignee: lispmeister
tags: [v1-io]
---
# Implement IO fault/status stream and debug log

Implement io_fault_status PubSub stream and local debug file logging for connection transitions, malformed observations, adapter errors, expired/duplicate/invalid commands, and reconnect/degraded/recovered states.

## Acceptance Criteria

IO publishes IoFaultStatusEvent values for configured fault types; core persists connection transitions always and other faults only when OODA-relevant or promoted for audit; debug log path is configurable; debug log is not authoritative, is not used for control decisions, is unbounded in V1, and redacts configured secrets.


## Notes

**2026-05-10T05:09:48Z**

2026-05-10 spec clarification update: IoFaultStatusEvent schema/prose must use fault_type with connection_up/connection_down/reconnecting/degraded/recovered/malformed_observation/adapter_execution_failed/adapter_rejected/command_expired/duplicate_idempotency_key/invalid_command_signature; connection transitions are always OODA-relevant, other faults conditional.
