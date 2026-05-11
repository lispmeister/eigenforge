---
id: eig-hcxs
status: closed
deps: []
links: [eig-eudn]
created: 2026-05-11T11:47:03Z
type: bug
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [v1-dashboard, bug]
---
# Keep dashboard state loading strictly read-only

Dashboard state loading currently calls core bootstrap validation, which can initialize the core SQLite ledger and write genesis during a page load. The dashboard must remain read-only and should determine the active room and load projections without mutating runtime state.

## Acceptance Criteria

Loading the LiveView dashboard never initializes or writes the core ledger; dashboard state resolution does not call bootstrap paths with side effects; tests cover an empty/missing ledger read path and verify no ledger events are created by dashboard access alone.

