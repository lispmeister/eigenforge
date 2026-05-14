---
id: eig-qzo1
status: closed
deps: []
links: []
created: 2026-05-14T07:48:18Z
type: chore
priority: 4
assignee: lispmeister
---
# Spec §6: note humidity and temperature are demo-only in V1, not load-bearing for control

Humidity and temperature are present in the V1 contract and dashboard but have zero decision coverage — they are observe-only. Their schema fields, source_status entries, dashboard surface, and ordering rules add complexity with no safety payoff in V1. Rather than removing them (already shipped, creates churn), add one sentence to §6 clarifying their status.

Proposed spec change: add to §6 (Normalized Snapshot Contract or the freshness section): 'Humidity and temperature fields are present in V1 for dashboard realism and to exercise multi-source freshness plumbing. They carry no control authority in V1 and may be removed in a V1.x simplification if the schema surface needs reducing.'

## Acceptance Criteria

§6 contains the clarifying sentence. No schema or code change.

