---
id: eig-bqzy
status: open
deps: [eig-o1sj, eig-q25o, eig-gu9r]
links: []
created: 2026-05-10T05:07:24Z
type: feature
priority: 1
assignee: lispmeister
parent: eig-rql0
tags: [next-slice, ledger, mailbox]
---
# Implement V1 command event chain references

Implement clarified command event chain references: action path persists policy_decision_recorded then command_envelope_issued; command.decision_event_id references the command_envelope_issued ledger event; command also carries policy_decision_id, reasoner_outcome_event_id, and capability_event_id for causal verification.

## Acceptance Criteria

Command delivery cannot occur until command_envelope_issued is committed; delivery receipt ledger_sequence and ledger_event_hash correspond to that committed event; verifier rejects missing or mismatched causal references.


## Notes

**2026-05-10T05:23:51Z**

SPEC-V1-FIXES-002 applied: command envelope/event chain now includes effect_key and command lifecycle states; command_envelope_issued starts in-flight physical-effect suppression.
