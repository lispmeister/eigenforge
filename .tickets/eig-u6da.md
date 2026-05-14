---
id: eig-u6da
status: closed
deps: []
links: []
created: 2026-05-14T07:47:59Z
type: task
priority: 3
assignee: lispmeister
---
# Spec §4: add explicit V1 threat model paragraph

The spec uses HMAC-with-shared-secret, canonical JSON, hash-chained ledger, detached config sidecars, and log redaction but never states who the adversary is or what the defenses do and do not cover. Without a stated threat model it is hard to judge whether each security mechanism is right-sized.

Proposed spec change: add one paragraph to §4 stating: V1 defends against (1) accidental or offline tampering with the ledger file at rest, (2) an external auditor verifying a ledger without trusting the authoring process, (3) accidental leakage of secrets in dashboard output or debug logs. V1 does NOT defend against compromise of the process holding EIGENFORGE_HMAC_SECRET in memory. Key separation, process isolation, and asymmetric crypto are explicitly V2/V3 work (already listed in §14). This drives whether shared-secret design, detached sidecars, and file permissions are understood as right-sized.

## Acceptance Criteria

§4 has a threat model paragraph with the three V1 defenses and the explicit non-defense against in-process compromise. §14 reference to V2/V3 asymmetric crypto is preserved.

