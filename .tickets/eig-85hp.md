---
id: eig-85hp
status: closed
deps: []
links: []
created: 2026-05-14T07:44:12Z
type: task
priority: 3
assignee: lispmeister
---
# Spec §9: define Mailbox.CommandTransport behavior; PubSub is one impl

§9 couples the spec to Phoenix PubSub for the core→IO command path, then layers receipt store, phase tracking, redelivery, and IO-side idempotency to compensate for PubSub's best-effort semantics. Expressing the boundary as a behavior decouples the contract from the transport, makes the delivery-receipt machinery the contract rather than a workaround, and keeps the door open for direct GenServer call or Oban delivery.

Proposed spec change: §9 specifies an Eigenforge.Mailbox.CommandTransport behavior with a publish_command/3 callback returning {:ok, delivery_evidence} | {:error, reason}. V1 ships a Mailbox.PubSubTransport implementation. §9 states explicitly which guarantees the spec assumes of the transport (best-effort delivery, no broker durability) and which the receipt store provides (durable receipt-before-publish, redelivery on restart). No code change in this ticket.

## Acceptance Criteria

§9 names the CommandTransport behavior and its required callback. §9 names PubSubTransport as the V1 implementation. The receipt and recovery rules in §9 are restated as transport requirements, not as workarounds for PubSub. No code change.

