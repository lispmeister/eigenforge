---
id: eig-777e
status: closed
deps: [eig-p9ms]
links: []
created: 2026-05-10T05:06:54Z
type: feature
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [next-slice, trace]
---
# Implement canonical time and deterministic trace identity helpers

Add shared helpers for strict V1 timestamp serialization/parsing and deterministic golden trace ids/clocks. Trace mode supplies fixed start time, process-local monotonic millisecond ticks, deterministic ids for trace/snapshot/source-observation/reasoner/capability/policy/consensus/event/command/receipt/after-action/adapter/correlation, and command expiry derived from issued_at.

## Acceptance Criteria

Golden trace generation is stable across repeated runs; deterministic source observation ids and receive ordering are stable; non-canonical timestamps are rejected in signed/ledger-relevant payloads; command expires_at equals issued_at plus configured TTL.
