---
id: eig-zp2l
status: open
deps: [eig-l5tk, eig-xtqn, eig-zohd]
links: [eig-l5tk, eig-runa, eig-xtqn]
created: 2026-05-10T05:36:53Z
type: feature
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [home-assistant, core, v1-io]
---
# Implement V1 Home Assistant manual-state and observation-ordering semantics

Implement Home Assistant manual/external state semantics after SPEC-V1-FIXES-004: split HA entity validation into static startup checks and dynamic post-connect validation, treat REST service success as accepted-not-confirmed, treat manual/external HA fan changes as observations not commands, use IO-local receive ordering rather than source wall time alone for post-delivery after-action confirmation, and preserve source timestamps plus local receive sequence for replayed HA events.

## Acceptance Criteria

Tests cover missing static HA config failing startup, dynamic wrong/missing entity validation entering degraded/no-physical-control state, REST success not producing confirmed_* status, old HA event replay ignored for command confirmation, manual fan on/off updating live state/effect_epoch, and manual observation resolving or contradicting a pending command only when IO-local receive ordering proves the observation arrived after delivery.
