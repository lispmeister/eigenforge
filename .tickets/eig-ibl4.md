---
id: eig-ibl4
status: open
deps: [eig-llbs, eig-60h5, eig-o1sj]
links: []
created: 2026-05-08T13:33:14Z
type: feature
priority: 1
assignee: lispmeister
tags: [next-slice]
---
# Decompose Trace into supervised core OODA pipeline

Spec §2 process layout: promote inline Trace functions to Core.SnapshotSubscriber, Core.CapabilityChecker, Core.PolicyEngine, Core.CommandIssuer, Core.AfterActionObserver under Core.Supervisor. Snapshots flow over PubSub io_state:room:ROOM_ID; finalized decisions append to the node-local SQLite command ledger before command delivery; commands flow via Mailbox.CommandPublisher on commands:io. Trace becomes a thin in-process harness.

## Acceptance Criteria

Simulator snapshot published on PubSub flows through the pipeline and appends the same node-local finalized ledger event chain a golden trace produces. No command is delivered until the local append-only ledger commit succeeds.

## Notes

**2026-05-09T14:00:19Z**

Aligned with revised spec: supervised OODA pipeline must append finalized decisions to node-local SQLite ledger before mailbox command delivery.
