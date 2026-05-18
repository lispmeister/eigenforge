# Applying A Layered Specification System To Prototype V1

Date: 2026-05-18

## Context

`SPECIFICATION-SYSTEMS.md` concluded that no single mature language fully
matches Eigenforge and Aether's desired specification system. The strongest
direction is a layered, repo-native specification stack:

```text
intent -> hazards/constraints -> requirements -> architecture -> contracts -> tests/proofs -> agent tasks
```

`PROTOTYPE-V1-SPEC.md` already contains many of these pieces implicitly:
stable invariants, component boundaries, schemas, canonicalization rules,
authority classes, golden traces, and implementation order. The main
improvement is to make those layers explicit and traceable instead of letting
long prose carry all semantic weight.

This note walks through `PROTOTYPE-V1-SPEC.md` section by section and describes
how to apply the specification-system survey to improve it.

## Overall Recommendation

Do not replace `PROTOTYPE-V1-SPEC.md` with a formal language yet. Evolve it
into a layered, traceable Markdown specification:

1. Add stable IDs to intent, hazards, requirements, contracts, invariants, and
   tests.
2. Add small structured tables where rules are currently buried in prose.
3. Add a traceability index from intent to requirement to contract to invariant
   to test.
4. Keep JSON Schema and golden traces as the executable contract layer.
5. Reserve deeper formal tools for command lifecycle, recovery, and the V2
   quorum transition.

The current spec's content is strong. The next maturity step is not more
detail. It is making the existing detail addressable, checkable, and hard for
humans or agents to misread.

## 1. Scope And Non-Goals

Current role: intent, scope, lifecycle, and implementation order.

Recommended improvement: split the opening into stable intent and scope
records.

Example:

```text
INTENT-V1-001: Prove a small inspectable control loop.
INTENT-V1-002: Preserve V2 quorum compatibility.
NON-GOAL-V1-001: No three-core quorum in V1.
SLICE-V1-001: Simulator-backed golden trace precedes Home Assistant.
```

This section should become the top of the trace tree. Every later invariant,
contract, test, and ticket should be able to point back to one of these IDs.

## 2. Architecture And App Responsibilities

Current role: component boundary specification. This is already close to a
SysML/AADL-style architecture model in prose form.

Recommended improvement: turn each app responsibility into a component
contract.

Example:

```text
COMP-V1-CORE
owns: OODA loop, ledger authority, after-action authorship
must_not: execute physical IO, write IO debug logs
inputs: normalized_snapshot, io_fault_status
outputs: ledger_event, command_envelope
```

The current prose is good, but agents would benefit from a machine-checkable
ownership table:

```text
component | allowed writes | forbidden writes | inputs | outputs | authority class
```

## 3. Runtime Modes

Current role: operational requirements and failure-mode behavior.

Recommended improvement: convert the startup matrix into EARS/FRETish-style
controlled requirements with stable IDs.

Example:

```text
REQ-RUNTIME-001:
WHEN EIGENFORGE_IO_MODE is home_assistant
AND HOME_ASSISTANT_TOKEN is missing
THE system SHALL fail startup before control loop begins.
```

The table is readable today, but not directly traceable to acceptance tests.
IDs would make it easier to generate tests and spot missing coverage.

## 4. Configuration And Signed Config

Current role: authority model, threat model, schemas, signing, and canonical
JSON.

Recommended improvement: split this section into three explicit layers:

```text
THREAT-V1-*      what V1 defends against
AUTH-V1-*        which payloads carry authority and why
CONTRACT-V1-*    schema/signature/canonicalization requirements
```

This is one of the most important sections of the spec. It already has a
strong formal profile. The main improvement is to make each canonicalization
and signing rule addressable.

Examples:

```text
CANON-V1-007: Duplicate object keys SHALL be rejected before canonicalization.
SIGN-V1-003: Ledger event signatures SHALL use purpose eigenforge:v1:ledger_event.
```

These IDs can then be cited by verifier errors, schema tests, golden traces,
and implementation tickets.

## 5. Device Inventory

Current role: domain model and static configuration.

Recommended improvement: separate domain facts from control constraints.

Domain facts:

```text
ROOM-V1: exactly one active room
SENSOR-V1-CO2: control-authoritative input
SENSOR-V1-HUMIDITY: observe-only input
ACTUATOR-V1-FAN: idempotent physical actuator
```

Control constraints:

```text
SAFE-V1-CO2-MISSING: Missing CO2 SHALL deny physical fan command.
SAFE-V1-FAN-OFF: Fan-off requires fresh CO2 below nominal minimum.
```

This is also where a STPA/STAMP-inspired layer could begin. For example,
"command fan off from stale CO2" is an unsafe control action. The spec already
says this in prose; the improvement is to name it and trace it.

## 6. Live IO Streams

Current role: input contract, freshness semantics, malformed input behavior,
and stream persistence boundary.

Recommended improvement: define a formal input contract plus a
decision-relevance table.

Example:

```text
source       status                         control effect
CO2          stale/missing/malformed         deny physical command
humidity     stale/missing/malformed         dashboard/fault context only
fan          unknown/stale                   allowed for idempotent fan only
```

The current text contains the rules, but they are distributed across the
section. A compact matrix would reduce ambiguity for agents implementing
normalizers, reasoners, dashboard state, and tests.

## 7. Reasoner, Control Rule, And OODA Loop

Current role: behavioral model.

Recommended improvement: define the OODA path as an explicit ordered
step model.

Example:

```text
OODA-V1-001 validate snapshot shape
OODA-V1-002 evaluate CO2 threshold
OODA-V1-003 apply actuator-state gate
OODA-V1-004 check capability
OODA-V1-005 evaluate policy
OODA-V1-006 finalize/persist
OODA-V1-007 issue command envelope
OODA-V1-008 observe after-action
```

The reasoner/gate separation is already strong and should be preserved. Later,
Quint, TLA+, Event-B, or another formal tool could model the control state, but
for V1 structured prose plus golden traces is probably enough.

## 8. Capabilities And Policy

Current role: authorization and policy contract.

Recommended improvement: separate capability semantics from policy decisions.

Capabilities answer:

```text
Is this subject granted this action on this target and scope?
```

Policy answers:

```text
Given reasoner outcome, freshness, actuator state, and capability result,
should physical action happen?
```

Add a policy decision table.

Example:

```text
reasoner outcome             capability checked?   policy decision
no_threshold_event            no                    no_command
insufficient_fresh_data       no                    deny_stale_snapshot
propose_no_action             no                    no_command
propose_action + grant allow  yes                   allow
propose_action + no grant     yes                   deny_missing_capability
```

This would make it harder for agents to blur capability checking, policy
evaluation, and actuator-state suppression.

## 9. Command Envelopes And Delivery

Current role: delivery protocol, idempotency, effect suppression, mailbox
boundary, and restart recovery.

Recommended improvement: promote this section to an explicit protocol spec.
It is the densest part of the document and the highest risk for implementation
drift.

Suggested split:

```text
PROTO-CMD-V1: command envelope fields and signing
PROTO-IDEM-V1: idempotency key derivation
PROTO-EFFECT-V1: effect key derivation and suppression
PROTO-MAILBOX-V1: receipt and phase behavior
PROTO-IO-ACCEPT-V1: IO pre-execution validation
RECOVERY-CMD-V1: restart matrix
```

The restart matrix is excellent. Give every row an ID so fault-injection tests
can cite it directly.

## 10. After-Action Observation

Current role: post-command truth model.

Recommended improvement: express authorship and ordering rules in controlled
natural language because they are safety-critical.

Examples:

```text
AA-V1-001:
ONLY core SHALL author terminal after-action status.

AA-V1-002:
An actuator observation SHALL confirm a command ONLY IF IO-local receive
ordering proves the observation arrived after command delivery.
```

This section also deserves an explicit status transition table from runtime
lifecycle state to terminal after-action state.

## 11. Local Core Ledger And Integrity

Current role: durable record model, invariants, append-only semantics, and
verification.

Recommended improvement: add a traceability map from invariant IDs to verifier
checks and tests.

Example:

```text
INV-07 -> LEDGER-APPEND-001 -> mix eigenforge.ledger.verify check -> ledger update rejected test
INV-09 -> LEDGER-HASH-001 -> verifier hash-chain check -> golden trace tamper test
```

This section is already close to a formal contract. It also contains V2
guidance, so V2 compatibility requirements should be marked separately from V1
executable requirements to avoid accidental scope creep.

Suggested labels:

```text
REQ-V1-*       executable V1 requirement
COMPAT-V1-*    V1 shape preserved for V2
DEFERRED-V2-*  do not implement in V1
```

## 12. Dashboard

Current role: read-only observability requirements.

Recommended improvement: define the dashboard as a projection/view contract.

Example:

```text
VIEW-V1-DASHBOARD
reads: live IO stream, latest_room_control_state, recent_control_chains
must_not: call Home Assistant, issue command, write ledger
must_display: io_mode, connection_status, latest readings, fan state, latest decision
```

The displayed statuses should be sourced from existing contracts rather than
dashboard-local wording. The current section already warns against label
confusion; making it contract-backed would help.

## 13. Test Rigs And Golden Traces

Current role: executable acceptance layer.

Recommended improvement: make this the explicit verification index for the
whole spec. Every golden trace should cite the requirement, invariant, and
contract IDs it proves.

Example:

```text
TRACE-V1-CO2-HIGH-FAN-OFF
covers:
  INTENT-V1-001
  OODA-V1-002
  POLICY-V1-ALLOW-001
  INV-01
  INV-02
  AA-V1-001
```

This is probably the best near-term place to apply the survey's lessons. A new
language is not required first; trace IDs and coverage links are.

## 14. Deferred V2/V3 Work

Current role: roadmap and compatibility guardrails.

Recommended improvement: split deferred work into two classes:

```text
COMPAT-V1-*     V1 must preserve this shape now for V2
DEFERRED-V2-*   do not implement in V1
```

This distinction matters for agents. "Keep fields shaped for quorum later" is
not the same as "build quorum now."

## Candidate Traceability Shape

A lightweight traceability block could be added to major spec sections without
leaving Markdown:

```text
id: OODA-V1-003
type: requirement
layer: behavior
statement: Core SHALL apply the actuator-state gate after reasoner output and before capability checking.
rationale: Keeps idempotency suppression outside pluggable reasoners.
upstream:
  - INTENT-V1-001
  - SAFE-V1-IDEMPOTENCY
downstream:
  - CONTRACT-V1-REASONER-OUTCOME
  - INV-03
  - TRACE-V1-CO2-HIGH-FAN-ON
```

This preserves human-readable Markdown while giving AI agents and future tools
enough structure to navigate, verify, and update the spec safely.

