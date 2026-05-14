---
id: eig-xpnq
status: open
deps: []
links: []
created: 2026-05-14T07:44:51Z
type: chore
priority: 3
assignee: lispmeister
---
# Add V1 demo script and acceptance walkthrough

Essence-captured is currently implicit in golden trace acceptance tests. A reproducible 5-10 minute demo script gives a concrete answer to: is the V1 prototype done?

Proposed change: add docs/v1-demo.md with a step-by-step script: (1) mix eigenforge.ledger.genesis against a clean DB, (2) start the umbrella in simulator mode, (3) push co2_high_fan_off fixture and observe fan-on appears in the dashboard, (4) inspect the ledger event chain and issued command envelope, (5) run mix eigenforge.ledger.verify and expect pass, (6) push co2_stale_fan_off and observe stale-deny chain and no command, (7) push co2_high_fan_on and observe propose_no_action chain.

## Acceptance Criteria

docs/v1-demo.md committed. Script runs end-to-end from a fresh checkout (no manual steps beyond following the script). All seven steps produce the documented output.


## Notes

**2026-05-14T07:57:04Z**

Spec updated: §13 V1 Acceptance Demo Script section describes the 7-step walkthrough. docs/v1-demo.md still needs to be committed.
