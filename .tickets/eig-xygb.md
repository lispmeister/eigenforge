---
id: eig-xygb
status: open
deps: []
links: []
created: 2026-05-14T05:54:47Z
type: chore
priority: 3
assignee: lispmeister
---
# Remove redundant LedgerProjections.init/1 call from apply_event

LedgerProjections.apply_event/2 calls init(db_path) before every event, which executes CREATE TABLE IF NOT EXISTS for both projection tables on every call. During startup projection rebuild this runs for every ledger row. init/1 should be called once at LedgerWriter startup (it already is via LedgerProjections.rebuild/1 which calls init/1 once at the top). The per-event call is redundant and adds unnecessary SQLite round-trips.

## Acceptance Criteria

apply_event/2 does not call init/1. LedgerProjections.init/1 is called exactly once per startup (via rebuild/1). All existing tests pass. A comment explains why init is not needed inside apply_event.

