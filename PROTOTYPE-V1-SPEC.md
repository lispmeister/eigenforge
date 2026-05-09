# Eigenforge Prototype V1 Implementation Spec

## 1. Scope And Non-Goals

V1 proves the input/output control loop while keeping the data model compatible
with later multi-core voting and quorum. The goal is a small, inspectable
control path:

```text
outside world
  -> IO live observation
  -> core OODA loop
  -> consensus/finalization boundary
  -> local core decision ledger
  -> signed command envelope
  -> IO execution
  -> core-authored after-action event
```

V1 covers:

- Home Assistant-backed sensor and actuator integration.
- Simulator mode for deterministic local testing and demos.
- One configured room, while all contracts retain `room_id`.
- CO2, humidity, temperature, and fan-state tracking.
- CO2-driven fan on/off decisions.
- Humidity and temperature as observe-only inputs.
- Static signed device inventory and capability grants.
- Schema-backed contract modules for control messages.
- A pluggable reasoner interface with a deterministic rules reasoner.
- Plain Elixir policy checks.
- Signed command envelopes.
- A signed, hash-chained, append-only local SQLite decision/action ledger for
  each core node.
- Live IO streams over Phoenix PubSub.
- A read-only Phoenix LiveView dashboard.
- Core logic tests, a golden trace runner, and golden trace acceptance tests
  independent of external IO.

V1 does not implement:

- three-core voting or quorum;
- LLM-backed reasoning;
- manual dashboard commands;
- hysteresis, debounce windows, or minimum actuator dwell time;
- historical sensor charts from InfluxDB;
- direct ESPHome control;
- application-level signatures from sensors or actuators;
- asymmetric cryptography or separated signing keys;
- external ledger anchoring;
- log rotation for IO debug files.

The V1 code should avoid shortcuts that make V2 quorum hard. V1 has one
effective core decision path and treats the single core as a one-member
consensus group, so the persistence boundary is the same shape as the later
post-quorum boundary.

### Implementation Order

Implementation starts with a simulator-backed golden trace vertical slice:

```text
simulator snapshot
  -> core reasoner
  -> capability check
  -> policy decision
  -> finalized decision/action
  -> local SQLite ledger event or events
  -> command envelope where applicable
  -> delivery receipt where applicable
  -> simulated IO execution where applicable
  -> core-authored after-action event where applicable
  -> ledger verification
```

Home Assistant integration and the dashboard must not precede a passing
simulator trace for the fan-on, no-action, and stale-deny cases.

## 2. Architecture And App Responsibilities

Use an Elixir umbrella project:

```text
eigenforge_umbrella
  apps/eigenforge_contracts
  apps/eigenforge_mailbox
  apps/eigenforge_io
  apps/eigenforge_core
  apps/eigenforge_dashboard
```

### App Responsibilities

`eigenforge_contracts` owns shared control-message contracts.

- Owns checked-in JSON Schemas for V1 contracts.
- Owns generated contract modules.
- Owns canonical JSON, hashing, HMAC signing, and verification helpers.
- Owns the contract generator and contract smoke/tests.
- Does not own runtime authority, IO, mailbox delivery, dashboard rendering, or
  durable ledger writing.

`eigenforge_io` owns the outside-world boundary.

- Interfaces with Home Assistant or the simulator.
- Normalizes outside sensor/actuator observations into live state.
- Publishes the live IO stream and the IO fault/status stream.
- Writes its IO fault/status stream to a local debug file.
- Receives command envelopes through the mailbox boundary.
- Verifies command envelope signature, expiry, and idempotency before
  execution.
- Executes valid command envelopes through the configured adapter.
- Does not decide, evaluate policy, write to core SQLite ledgers, or author
  after-action truth.

`eigenforge_core` owns the OODA loop and authority.

- Subscribes to the live IO stream and IO fault/status stream.
- Validates live input shape, freshness, and decision relevance.
- Runs the reasoner, capability checks, policy checks, and actuator-state gate.
- Finalizes decisions through the configured consensus boundary.
- Persists finalized decision/action ledger records to the local SQLite ledger.
- Persists a finalized decision/action record before any command is sent to IO.
- Issues signed command envelopes after local ledger commit.
- Observes IO state/faults after command delivery and records after-action
  events.

`eigenforge_mailbox` is a dumb channel manager.

- Accepts, stores, routes, and delivers messages where applicable.
- Manages channels, topics, lightweight notifications, and supported read
  projections.
- Maintains read projections only as mechanical read models over committed
  ledger records; projections do not grant authority or reinterpret events.
- Delivers command envelopes to IO through the mailbox boundary only after the
  corresponding local ledger commit.
- May read envelope identifiers required for routing, projection, and delivery
  receipts.
- Does not validate signatures, evaluate policy, decide authorization, change
  payload fields, enrich command semantics, or mutate message contents.
- Does not decide whether a command is allowed.

`eigenforge_dashboard` is read-only in V1.

- Subscribes to live IO streams for current state and fault/status display.
- Reads durable decision/action history and projections.
- Does not mutate system state, issue manual commands, or call Home Assistant.

### Core Consensus And Persistence Model

Each core node owns a local SQLite database. Core persistence is for finalized
control facts only: reasoner outcomes, capability checks, policy decisions,
issued command envelopes, relevant IO faults, and after-action events. Core
does not store bulk sensor telemetry or actuator state history.

V1 runs with one effective core node. That node is treated as a one-member
consensus group: once the deterministic OODA path reaches a final decision, the
node persists the finalized decision/action events to its local SQLite ledger
before any command envelope is delivered to IO.

V2 replaces the one-member finalization boundary with three core nodes and
2-of-3 quorum. After quorum, each participating core node persists the
finalized action chain to its own local SQLite ledger. A node that did not
participate in quorum must not independently issue a command from stale local
state; it must append local catch-up evidence for signed finalized decisions
before it can act as a command finalizer.

Network split rule:

- a partition with quorum may finalize and persist decisions locally on the
  participating core nodes;
- a partition without quorum may continue observing IO and preparing local
  proposals, but it must not finalize, persist action-authorizing decisions, or
  issue command envelopes;
- when a partition heals, nodes compare signed finalized decisions by
  `consensus_decision_id`, `correlation_id`, idempotency key, and quorum
  evidence before appending local catch-up records;
- IO executes at most one command for a finalized decision because command
  envelopes carry idempotency keys and references to finalized ledger events.

### Suggested OTP Process Layout

Names are implementation guides, not mandatory module names:

```text
eigenforge_contracts
  Contracts.DeviceInventory
  Contracts.CapabilityGrant
  Contracts.CapabilityCheck
  Contracts.PolicyDecision
  Contracts.NormalizedSnapshot
  Contracts.ReasonerOutcome
  Contracts.CommandEnvelope
  Contracts.DeliveryReceipt
  Contracts.AfterActionEvent
  Contracts.IoFaultStatusEvent
  Contracts.LedgerEvent

eigenforge_io
  IO.Supervisor
  IO.AdapterSupervisor
  IO.HomeAssistantClient
  IO.SimulatorClient
  IO.SnapshotNormalizer
  IO.CommandExecutor
  IO.FaultStatusLog

eigenforge_core
  Core.Supervisor
  Core.SnapshotSubscriber
  Core.FaultStatusSubscriber
  Core.Reasoner
  Core.CapabilityChecker
  Core.PolicyEngine
  Core.CommandIssuer
  Core.AfterActionObserver

eigenforge_mailbox
  Mailbox.Supervisor
  Mailbox.ChannelManager
  Mailbox.CommandPublisher
  Mailbox.LedgerNotifier
  Mailbox.Projections

eigenforge_dashboard
  Dashboard.Endpoint
  Dashboard.LiveView
```

## 3. Runtime Modes

Runtime mode is selected at startup:

```text
EIGENFORGE_IO_MODE=home_assistant
EIGENFORGE_IO_MODE=simulator
```

### Home Assistant Mode

Home Assistant mode uses:

- Home Assistant WebSocket API for sensor and actuator state ingest.
- Home Assistant REST API for fan command execution.

V1 treats the fan entity as a Home Assistant `switch` entity:

```text
requested_state=on
POST /api/services/switch/turn_on
body: {"entity_id": HA_FAN_ENTITY_ID}

requested_state=off
POST /api/services/switch/turn_off
body: {"entity_id": HA_FAN_ENTITY_ID}
```

V1 Home Assistant mode can start degraded when Home Assistant is unreachable.
The dashboard must show disconnected/degraded state, and IO should retry
connection with logarithmic backoff:

```text
initial retry: 5 seconds
maximum retry: 3 minutes
config env: EIGENFORGE_HA_RECONNECT_MAX_MS=180000
```

Missing or invalid required configuration still fails startup.

### Simulator Mode

Simulator mode is for tests and local demos. It must not connect to Home
Assistant, InfluxDB, ESPHome, MQTT, or any other outside data source.

Simulator mode uses static JSON normalized snapshot fixtures under:

```text
config/simulator_snapshots
```

Simulator fixtures may be unsigned in V1. They are test/demo inputs, not
authority-bearing runtime config. Decisions produced from simulator snapshots
are still signed and persisted normally.

The simulator should use the same normalized snapshot and command envelope
contracts as Home Assistant mode. The dashboard must clearly show simulator
mode when active.

## 4. Configuration And Signed Config

Secrets and local Home Assistant settings live in a project-root `.env` file
ignored by git.

Commit `.env.example` with placeholders:

```text
HOME_ASSISTANT_URL=http://homeassistant.local:8123
HOME_ASSISTANT_TOKEN=replace_me
EIGENFORGE_HMAC_SECRET=replace_me
HA_CO2_ENTITY_ID=sensor.placeholder_co2
HA_HUMIDITY_ENTITY_ID=sensor.placeholder_humidity
HA_TEMPERATURE_ENTITY_ID=sensor.placeholder_temperature
HA_FAN_ENTITY_ID=switch.placeholder_fan
EIGENFORGE_AFTER_ACTION_TIMEOUT_MS=3000
EIGENFORGE_IO_MODE=home_assistant
EIGENFORGE_HA_RECONNECT_MAX_MS=180000
EIGENFORGE_IO_FAULT_STATUS_LOG=log/io_fault_status.log
EIGENFORGE_CORE_NODE_ID=core_a
EIGENFORGE_CORE_DB_PATH=var/core/core_a.sqlite3
```

In `home_assistant` mode, the app must fail fast if required Home Assistant
values or `EIGENFORGE_HMAC_SECRET` are missing. In simulator mode, Home
Assistant values are not required because simulator mode must not connect to
outside services.

V1 uses one shared secret for all HMAC signatures:

```text
EIGENFORGE_HMAC_SECRET
```

This secret signs:

- device inventory config;
- capability grants;
- delivery receipts;
- command envelopes;
- durable decision/action ledger events.

Key separation is deferred.

### Signed JSON Requirements

Signed JSON payloads must include:

```text
format_version
schema_id
schema_version
```

V1 validates signed JSON payloads against checked-in JSON Schemas under:

```text
priv/schemas
```

At minimum, schemas should exist for:

- device inventory;
- capability grants;
- capability checks;
- policy decisions;
- normalized snapshots;
- reasoner outcomes;
- command envelopes;
- delivery receipts;
- after-action events;
- IO fault/status events;
- durable ledger event payloads.

The verifier rejects signed payloads whose declared `schema_id` and
`schema_version` do not match a known local schema.

### Contract Compiler

`priv/schemas` is the V1 source of truth for control message contracts. The
project should include a contract generator that reads checked-in JSON Schemas
and emits Elixir contract modules.

Generated contract modules should provide:

- struct fields and basic type metadata;
- required-field validation;
- canonical JSON encoding;
- payload hashing;
- HMAC signing and verification helpers;
- stable display/fixture maps for golden traces.

No V1 app should hand-roll message maps for signed or ledger-relevant
contracts. Core, IO, mailbox, dashboard, config signing, ledger writing, and
golden trace tooling should use generated contract modules where practical.

The initial contract modules should cover:

```text
Eigenforge.Contracts.DeviceInventory
Eigenforge.Contracts.CapabilityGrant
Eigenforge.Contracts.CapabilityCheck
Eigenforge.Contracts.PolicyDecision
Eigenforge.Contracts.NormalizedSnapshot
Eigenforge.Contracts.ReasonerOutcome
Eigenforge.Contracts.CommandEnvelope
Eigenforge.Contracts.DeliveryReceipt
Eigenforge.Contracts.AfterActionEvent
Eigenforge.Contracts.IoFaultStatusEvent
Eigenforge.Contracts.LedgerEvent
```

This establishes a V1 control message ABI:

```text
schema -> generated contract module -> canonical JSON -> signature/hash -> golden trace
```

### Canonical JSON And Signing

V1 uses canonical JSON for signatures and hashes.

Canonicalization rules:

- encode as UTF-8 JSON;
- sort object keys lexicographically;
- emit no insignificant whitespace;
- use normal JSON string escaping;
- preserve integers as integers;
- avoid floats in signed payloads where possible;
- represent fractional values as scaled integers or strings when they need to
  be signed;
- represent timestamps as ISO-8601 UTC strings with millisecond precision;
- exclude detached signature sidecars from the payload they sign;
- for command envelopes, `payload_hash` covers the command body excluding
  `payload_hash` and `signature`;
- for command envelopes, `signature` covers the command body including
  `payload_hash` but excluding `signature`;
- for ledger events, `payload_hash` covers `payload` only;
- for ledger events, `event_hash` covers the ledger envelope excluding
  `event_hash` and `signature`;
- for ledger events, `signature` covers the ledger envelope including
  `event_hash` but excluding `signature`;
- for detached config sidecars, `payload_hash` covers the config payload;
- for detached config sidecars, `signature` covers the sidecar body including
  `payload_hash` and `signature_version`, excluding `signature`.

Use the same canonicalization implementation for config signing, capability
grant signing, command envelope signing, ledger writing, and ledger
verification.

The serialization format must remain evolvable. V1 uses canonical JSON because
it is inspectable and easy to test. Future versions may add compact binary
formats without changing semantic contracts because every signed payload
declares `format_version`, `schema_id`, and `schema_version`.

### Detached Signature Sidecars

Runtime config and capability signatures are detached sidecar files:

```text
config/devices.json
config/devices.json.sig

config/capabilities/core_rule_stub_fan.json
config/capabilities/core_rule_stub_fan.json.sig
```

The signature sidecar contains:

```text
payload_hash
signature_version
signature
```

In `home_assistant` mode, startup fails when required runtime device inventory
or capability config is missing, malformed, unsigned, or has an invalid
signature. In simulator mode, unsigned test/demo config may be allowed.

Add signing helpers:

```text
mix eigenforge.config.sign --in config/devices.json --sig config/devices.json.sig

mix eigenforge.capability.grant \
  --subject core_rule_stub \
  --target actuator:fan \
  --action command_actuator \
  --scope room:placeholder \
  --out config/capabilities/core_rule_stub_fan.json \
  --sig config/capabilities/core_rule_stub_fan.json.sig
```

## 5. Device Inventory

The device inventory is the source of truth for available sensors, actuators,
room identity, Home Assistant entity mappings, units, actuator capabilities,
and actuator idempotency metadata.

V1 supports one room, but all contracts keep `room_id`.

Example:

```text
config/devices.json
```

```json
{
  "format_version": "json-canonical-v1",
  "schema_id": "eigenforge.device_inventory",
  "schema_version": 1,
  "rooms": [
    {
      "room_id": "placeholder",
      "sensors": [
        {
          "sensor_id": "co2",
          "kind": "co2",
          "entity_id_env": "HA_CO2_ENTITY_ID",
          "unit": "ppm",
          "transport_security": "esphome_noise_via_home_assistant",
          "nominal_min": 500,
          "nominal_max": 1000
        },
        {
          "sensor_id": "humidity",
          "kind": "humidity",
          "entity_id_env": "HA_HUMIDITY_ENTITY_ID",
          "unit": "percent",
          "transport_security": "esphome_noise_via_home_assistant",
          "observe_only": true
        },
        {
          "sensor_id": "temperature",
          "kind": "temperature",
          "entity_id_env": "HA_TEMPERATURE_ENTITY_ID",
          "unit": "celsius",
          "transport_security": "esphome_noise_via_home_assistant",
          "observe_only": true
        }
      ],
      "actuators": [
        {
          "actuator_id": "vent_fan",
          "kind": "fan",
          "entity_id_env": "HA_FAN_ENTITY_ID",
          "actions": ["on", "off"],
          "transport_security": "home_assistant_rest",
          "idempotent": true
        }
      ]
    }
  ]
}
```

V1 actuator idempotency:

```text
fan on/off: idempotent
lights on/off stub: idempotent placeholder
laser on/off stub: non-idempotent/safety-sensitive placeholder
piezo beeper pulse: non-idempotent placeholder
```

Only the fan has physical command execution in V1. Light, laser, and piezo
stubs may exist as adapter placeholders, but they return without physical
action.

Each sensor and actuator should record `transport_security`. Missing metadata
produces a startup warning and displays as `unknown`; it does not fail V1
startup.

For ESPHome/Home Assistant deployments, assume ESPHome Native API Noise
encryption via Home Assistant by default:

```text
esphome_noise_via_home_assistant
```

This is transport-layer security only. ESPHome sensor readings do not have
per-reading application signatures in V1. Later versions should require
application-level signatures from sensors and actuators.

## 6. Live IO Streams

The live IO stream is the current Home Assistant or simulator sensor/actuator
state stream. It is not persisted to core SQLite as a historian.

IO publishes normalized snapshots over Phoenix PubSub. Suggested topics:

```text
io_state:room:ROOM_ID
io_fault_status
commands:io
```

Core subscribes to:

- live IO stream;
- IO fault/status stream.

Dashboard subscribes to:

- live IO stream;
- IO fault/status stream.

Ephemeral IO streams are not signed in V1. Incoming sensor, actuator, and fault
data is not trusted by default. Core validates shape, freshness, capability,
policy, and actuator state before deciding anything durable.

### Normalized Snapshot Contract

Each normalized snapshot should include:

```text
format_version
schema_id
schema_version
snapshot_id
snapshot_seq
snapshot_hash
room_id
co2_ppm
humidity_percent
temperature_c
fan_state
source_entity_ids
source_observed_at
source_status
normalized_at
freshness
```

`freshness` is either:

```text
fresh
stale
```

`source_status` records freshness or availability for each input source:

```json
{
  "co2": "fresh",
  "humidity": "fresh",
  "temperature": "stale",
  "fan": "unknown"
}
```

Allowed source status values:

```text
fresh
stale
unknown
malformed
missing
unavailable
```

Decision relevance:

- CO2 stale, missing, malformed, unavailable, or unknown means no physical
  command may be issued; core records a stale/deny/no-command path.
- Humidity and temperature are observe-only in V1. Their stale, missing,
  malformed, unavailable, or unknown status is shown as dashboard/fault context
  but does not itself deny fan action.
- Fan state stale or unknown still permits fan on/off commands because the fan
  actuator is idempotent. Non-idempotent actuators must not receive blind
  commands.

Unknown, unavailable, malformed, or missing Home Assistant values should not
crash the pipeline. They should be represented as rejected live observations.
If they affect decision safety, core records the relevant durable
decision/action event after observing them.

### IO Fault/Status Stream

IO publishes adapter execution errors, transport failures, malformed
outside-world responses, reconnects, and outside connection state transitions
to the IO fault/status stream.

V1 IO fault/status `fault_type` values:

```text
connection_up
connection_down
reconnecting
degraded
recovered
malformed_observation
adapter_execution_failed
adapter_rejected
command_expired
duplicate_idempotency_key
invalid_command_signature
```

Malformed, unavailable, unknown, or missing outside values are not published as
valid normalized snapshots. IO emits an `IoFaultStatusEvent` with
`fault_type=malformed_observation` or the closest applicable fault type. Core
persists the fault only when it affects OODA or decision context. Malformed or
missing CO2 causes a stale/deny/no-command path. Malformed humidity or
temperature is dashboard/fault context only in V1.

The IO fault/status stream is ephemeral. IO must not write it to core SQLite.
Core observes the stream and persists connection/fault events to its local
decision ledger only when they affect OODA or decision context.

All outside connection state transitions affect the OODA loop and must be
persisted by core after observation. This includes:

- connection up;
- connection down;
- reconnecting;
- degraded;
- recovered.

This applies to Home Assistant, simulator channels, later InfluxDB access, and
actuator command channels.

For debugging, IO also writes its IO fault/status stream to:

```text
log/io_fault_status.log
```

The path is configurable with:

```text
EIGENFORGE_IO_FAULT_STATUS_LOG
```

This file is not authoritative, is not part of the durable decision/action
ledger, and is not used for control decisions. Rotation is deferred.

## 7. Reasoner, Control Rule, And OODA Loop

The V1 control rule is deterministic:

```text
CO2 nominal range: 500..1000 ppm

if CO2 > nominal maximum:
  propose fan on

if CO2 < nominal minimum:
  propose fan off

otherwise:
  no action
```

Humidity and temperature are included in normalized snapshots and dashboard
state, but they are observe-only in V1.

Values inside nominal range produce no action by default. Values outside
nominal range enter the reasoner.

Flutter, hysteresis, debounce windows, and dwell time are deferred. V1 only
avoids redundant commands when the actuator is already in the requested state.

### Reasoner Interface

The reasoner is pluggable from the start. Core calls a reasoner
behavior/interface with a normalized snapshot and receives a normalized
reasoner outcome. V1 ships a deterministic rules reasoner; later versions can
add LLM reasoners without changing IO, policy, command envelope, or ledger
boundaries.

Reasoner outcome types:

```text
propose_action
propose_no_action
no_threshold_event
insufficient_fresh_data
```

Reasoner output should include:

```text
reasoner_id
reasoner_version
snapshot_id
snapshot_hash
outcome_type
target
requested_state
reason
confidence_bps
metadata
```

Use integer basis points for confidence:

```text
confidence_bps
```

`10000` means 100.00 percent. `7500` means 75.00 percent. V1 does not use
floating-point confidence values in signed payloads. For deterministic V1
rules, `confidence_bps` may be `10000`.

Example reasons:

```text
CO2 1240 ppm exceeds 1000 ppm threshold; propose vent fan ON.
Threshold reached but no action due to CO2 fan actuator already in state ON.
Threshold reached but no action due to CO2 fan actuator already in state OFF.
```

### Actuator-State Gate

The actuator-state gate is inside the core OODA loop.

After core observes a CO2 threshold breach, it evaluates the latest fan state
from the normalized snapshot before proposing a physical command.

If threshold is breached but the fan is already in the requested state, core
records a no-action reasoner outcome:

```text
Threshold reached but no action due to CO2 fan actuator already in state ON.
Threshold reached but no action due to CO2 fan actuator already in state OFF.
```

This no-action rule applies symmetrically to fan-on and fan-off. In V2, core
nodes vote on this normalized no-action outcome the same way they vote on a
physical action. V1 records the same normalized outcome shape.

If fan state is unknown or stale and CO2 requires action, core may still send
the fan command because fan on/off is idempotent. Non-idempotent actuators must
not receive blind commands. Actuator idempotency comes from device inventory
config.

### Timing Defaults

```text
snapshot stale after: 15 seconds
command envelope expires after: 5 seconds
after-action confirmation timeout: 3 seconds
```

`EIGENFORGE_AFTER_ACTION_TIMEOUT_MS` configures after-action timeout.

If CO2 is stale, core records a stale/deny decision and sends no actuator
command.

## 8. Capabilities And Policy

Capabilities are static signed grants loaded at startup. V1 grant revocation,
delegation, and expiration are deferred.

Capability grant JSON contains:

```text
format_version
schema_id
schema_version
grant_id
subject
target
action
scope
issued_at
```

Capability checks are first-class generated contracts and persisted as ledger
events.

```text
Eigenforge.Contracts.CapabilityCheck
priv/schemas/capability_check.schema.json
```

Capability check payloads contain:

```text
format_version
schema_id
schema_version
capability_check_id
subject
target
action
scope
grant_id
result
reason
checked_at
```

Allowed capability check `result` values:

```text
allow
deny_missing_capability
deny_invalid_capability
```

Initial grant example:

```text
subject: core_rule_stub
target: actuator:fan
action: command_actuator
scope: room:placeholder
```

V1 policy checks are plain Elixir functions, not a DSL.

Initial policy behavior:

- allow fan on/off only when a valid signed capability grant exists;
- allow no physical execution for lights, laser, and beeper stubs;
- deny unsupported adapter actions;
- deny commands based on stale snapshots;
- deny blind commands for unknown/stale non-idempotent actuator state;
- record every policy decision as a signed durable decision/action event.

Policy decision results:

```text
allow
deny_missing_capability
deny_invalid_capability
deny_stale_snapshot
deny_unknown_non_idempotent_actuator_state
deny_expired_command
deny_unsupported_action
noop_stub
deny_rate_limited
```

The "already in desired state" case is a reasoner `propose_no_action` outcome,
not a policy denial.

Every policy decision persisted to the ledger should include the capability
grant, missing capability, or invalid capability that determined the result.

Policy decisions are first-class generated contracts and persisted as ledger
events.

```text
Eigenforge.Contracts.PolicyDecision
priv/schemas/policy_decision.schema.json
```

Policy decision payloads contain:

```text
format_version
schema_id
schema_version
policy_decision_id
snapshot_id
snapshot_hash
reasoner_outcome_id
subject
target
action
scope
requested_state
decision
capability_grant_id
capability_status
reason
decided_at
metadata
```

## 9. Command Envelopes And Delivery

Every command sent to IO uses a signed command envelope:

```text
format_version
schema_id
schema_version
command_id
idempotency_key
subject
target
action
scope
requested_state
snapshot_id
snapshot_seq
decision_event_id
reasoner_outcome_event_id
capability_event_id
policy_decision_id
issued_at
expires_at
payload_hash
signature_version
signature
```

Command envelopes are signed with `EIGENFORGE_HMAC_SECRET`.

Core must finalize and persist the corresponding decision/action ledger record
before any command is sent to IO. In V1, finalization is the one-member core
decision. In V2, finalization requires quorum evidence.

If local SQLite persistence fails, the core ledger writer retries the failed
transaction three times. If all attempts fail, it returns
`{:error, :ledger_persistence_failed}` to callers and the runtime process
responsible for command issuance raises. No command is delivered after failed
persistence. Golden traces and tests assert the error result and no IO command
delivery; they do not need to crash the VM.

V1 assumes persistence is reliable once SQLite commits the local ledger
transaction. V2 requires each quorum participant to persist the finalized
decision to its own SQLite ledger; a finalizer must not issue the command until
its own local commit succeeds.

Command delivery to IO uses Phoenix PubSub through the mailbox boundary after
local ledger commit. The mailbox publishes to an explicit command topic such
as:

```text
commands:io
```

The mailbox may read the command identifiers required to route the envelope and
create the delivery receipt. It must not validate signatures, evaluate policy,
authorize execution, change payload fields, enrich command semantics, or mutate
the command envelope.

After the corresponding ledger event is committed, the mailbox attaches a
signed delivery receipt to command delivery. The receipt is mechanical delivery
metadata, not authorization.

```text
Eigenforge.Contracts.DeliveryReceipt
priv/schemas/delivery_receipt.schema.json
```

Delivery receipt payloads contain:

```text
format_version
schema_id
schema_version
receipt_id
command_id
decision_event_id
ledger_sequence
ledger_event_hash
delivered_topic
delivered_at
signature_version
signature
```

Before execution, IO verifies:

- command envelope signature is valid;
- delivery receipt signature is valid;
- envelope has not expired;
- `receipt.command_id` equals `command.command_id`;
- `receipt.decision_event_id` equals `command.decision_event_id`;
- delivery receipt metadata indicates the referenced decision event was
  committed;
- `idempotency_key` has not already been executed.

IO does not connect directly to any core SQLite database in V1.

## 10. After-Action Observation

The ledger distinguishes the decision to act from what core observed after IO
attempted execution.

After-action status is detected and recorded by core, not authored by IO. IO
publishes live actuator state changes and IO fault/status events; core
interprets those observations and records after-action events.

Expected action chain:

1. IO publishes a live snapshot showing CO2 above the fan-on threshold.
2. Core decides to request fan activation.
3. Core finalizes the decision and persists the command envelope to its local
   SQLite decision/action ledger.
4. The command envelope is delivered to IO through the mailbox boundary.
5. IO sends the command to the Home Assistant or simulator fan adapter.
6. IO continues publishing live actuator state changes and IO fault/status
   events.
7. Core observes the resulting streams as part of its OODA loop.
8. Core records an after-action event linked to the original command envelope.

After-action event payload should include:

```text
after_action_id
command_id
idempotency_key
adapter_attempt_id
target
requested_state
observed_state
status
observed_at
reported_at
source_observation_ids
source_fault_event_ids
```

Supported `status` values:

```text
confirmed_changed
confirmed_already_in_state
command_sent_but_unconfirmed
adapter_rejected
adapter_failed
state_mismatch
timed_out
```

For Home Assistant, IO should prefer observed fan state from the HA event
stream after the REST command. If no confirming state event arrives within the
configured timeout, core records `command_sent_but_unconfirmed` or `timed_out`
based on observed live state and IO fault/status events. IO execution errors
caught locally are published on the IO fault/status stream for core to observe
and record where relevant.

## 11. Local Core Ledger And Integrity

Each core node has a local SQLite database that stores its durable
decision/action ledger. The ledger is not the sensor historian.

Do not persist the live stream of sensor observations or routine normalized
snapshots to core SQLite. Home Assistant and InfluxDB own live and historical
sensor telemetry. InfluxDB access is deferred and only for later history,
diagnostics, or charting. Core only stores the OODA decisions and control facts
needed to explain and verify actions over time.

The local decision/action ledger records what a core node finalized, which live
state summary or hash it used, which capability and policy checks allowed or
denied the action, which command envelope was issued, what relevant IO faults
or state changes core observed afterward, and what after-action status core
recorded.

In V1, the single core node finalizes its own decision before local persistence.
In V2, a ledger row that authorizes action must reference quorum evidence for a
finalized consensus decision. A node on the non-quorum side of a network split
may keep volatile observations and candidate proposals, but it must not persist
action-authorizing ledger events or issue command envelopes.

### Ledger Event Envelope

Persist durable events with this envelope:

```text
event_id
sequence
event_type
core_node_id
consensus_decision_id
consensus_status
quorum_ref
causation_id
correlation_id
subject
source_app
occurred_at
observed_at
persisted_at
payload
payload_hash
previous_event_hash
event_hash
signature_version
signature
```

`event_id` is globally unique. `sequence` is assigned by the local SQLite
ledger insert path for one core node. `core_node_id` identifies the writer.
`consensus_decision_id` identifies the finalized decision across core nodes.
`consensus_status` is `single_core_finalized` in V1 and `quorum_finalized` in
V2. `quorum_ref` is empty in V1 and points to quorum evidence in V2.
`causation_id` points to the event that directly caused this event.
`correlation_id` groups the full causal chain. `payload` contains an
event-type-specific signed JSON payload with `format_version`, `schema_id`,
and `schema_version`.

Routine normalized snapshots are not ledger events. Durable events may include
snapshot summaries, `snapshot_id`, `snapshot_seq`, and `snapshot_hash` when a
reasoner outcome, policy decision, command envelope, or after-action event
needs to refer to the live state that caused it.

Persist signed durable events for:

- outside connection state transitions observed by core;
- IO faults that affect OODA or decision context;
- stale sensor deny decisions;
- reasoner outcomes;
- capability checks;
- policy decisions;
- command envelopes;
- core-recorded after-action events;
- node faults and restarts where practical.

V1 ledger `event_type` values are fixed:

```text
ledger_genesis
connection_status_observed
io_fault_observed
reasoner_outcome_recorded
capability_check_recorded
policy_decision_recorded
command_envelope_issued
after_action_recorded
stale_snapshot_denied
node_fault_observed
```

The ledger writer rejects unknown event types.

V2 may add explicit proposal, vote, quorum certificate, catch-up, and
partition-status event types, but action-authorizing events must still use the
same finalized command path.

### Hash Chain

Local ledger requirements:

- events are append-only;
- normal application code cannot update or delete existing ledger rows;
- every event is signed with HMAC-SHA256;
- every event records `core_node_id`;
- every action-authorizing event records a finalized `consensus_decision_id`;
- every event stores its canonical `payload_hash`;
- every event includes `previous_event_hash`;
- `payload_hash` covers `payload` only;
- `event_hash` covers the canonical ledger envelope excluding `event_hash` and
  `signature`;
- `signature` covers the canonical ledger envelope including `event_hash` but
  excluding `signature`;
- projection tables are derived and can be rebuilt from the ledger.

Each local core ledger starts with a signed genesis event created before normal
runtime:

```text
mix eigenforge.ledger.genesis
```

The genesis event is sequence `1`:

```text
event_type=ledger_genesis
sequence=1
previous_event_hash=eigenforge-ledger-genesis-v1
```

Its payload records immutable ledger identity:

```text
format_version
schema_id
schema_version
ledger_id
core_node_id
created_at
genesis_reason
app_version
```

Runtime startup must verify the genesis event before appending later events.
Event `2` and later set `previous_event_hash` to the previous row's
`event_hash`.

The local SQLite ledger insert path should run in a transaction that:

1. Begins an immediate write transaction.
2. Reads the latest `event_hash`.
3. Assigns the next `sequence`.
4. Computes `previous_event_hash`, `payload_hash`, and `event_hash`.
5. Inserts the event.
6. Updates separate projection tables derived from the inserted event.
7. Commits.

A single writer process per core node is required. SQLite must run in WAL mode
for local read concurrency, but ledger appends still go through one writer so
two runtime processes cannot claim the same local ledger tail.

Database constraints should support:

- unique monotonic `sequence`;
- unique `event_id`;
- unique `event_hash`;
- required `core_node_id`;
- required `consensus_status`;
- required `previous_event_hash`;
- required `payload_hash`;
- required `signature`;
- sequence `1` must be `ledger_genesis`;
- sequence `1` must use
  `previous_event_hash=eigenforge-ledger-genesis-v1`;
- no runtime code path for updating, deleting, replacing, resequencing, or
  backfilling ledger rows.

V1 enforces append-only ledger behavior with application code, SQLite triggers
that reject `UPDATE` and `DELETE` on ledger rows, and cryptographic
verification. Ledger writes must use plain inserts only. Runtime code must not
use `INSERT OR REPLACE`, `ON CONFLICT DO UPDATE`, table rebuild/swap flows, or
catch-up paths that rewrite existing ledger rows. File permissions and process
boundaries should keep each local database writable only by its owning core
node runtime.

Implement HMAC/hash calculation in application code so the writer and
verification task use the same canonical rules.

### Projections And Notifications

The append-only ledger table is authoritative. Projection tables are
convenience read models only. If a local projection disagrees with the local
ledger, the ledger wins and the projection should be rebuilt.

Projection rows may be updated, deleted, or rebuilt because they are not the
ledger. Those mutations must never modify `ledger_events`, change local ledger
sequence numbers, or alter any previous ledger hash.

Minimal tables:

```text
ledger_events
latest_room_control_state
recent_control_chains
```

`latest_room_control_state` contains:

```text
room_id
latest_snapshot_id
latest_snapshot_hash
co2_ppm
humidity_percent
temperature_c
fan_state
io_mode
connection_status
latest_reasoner_outcome_id
latest_policy_decision_id
latest_command_id
latest_after_action_id
updated_at
```

`recent_control_chains` contains:

```text
correlation_id
room_id
started_at
latest_event_id
latest_event_type
snapshot_id
reasoner_outcome
policy_decision
command_id
after_action_status
updated_at
```

Use local PubSub/process notifications only as wakeups for predefined
decision/action subscriptions and dashboard updates. Notifications should carry
lightweight identifiers such as `core_node_id`, `event_id`, `event_type`, or
projection names. Consumers re-read from the local SQLite ledger or projection
tables instead of treating notification payloads as authoritative history.

### Multi-Core Catch-Up And Network Splits

V2 quorum decisions are durable only after a node has verified quorum evidence
and committed the finalized event chain to its own local ledger. A quorum
certificate should include:

```text
consensus_decision_id
snapshot_id
snapshot_hash
proposed_action_or_no_action
supporting_core_node_ids
supporting_vote_ids
supporting_vote_hashes
finalizer_core_node_id
finalized_at
```

Catch-up is append-only. A lagging node must not copy foreign ledger rows into
its own `ledger_events` table, preserve a foreign `sequence`, reuse a foreign
`event_hash` as its own event hash, or splice missing records into the middle
of its local chain. Instead, it appends one or more local catch-up events whose
payload contains or references the signed finalized decision, supporting vote
hashes, foreign node ids, and any foreign event hashes as evidence. The local
catch-up event receives the next local `sequence`, points `previous_event_hash`
at the node's own ledger tail, and computes a new local `event_hash`.

Split-brain safety rules:

- a 2-of-3 partition may finalize decisions;
- a 1-of-3 partition may observe, reason, and prepare unsigned or
  non-authorizing local diagnostics, but it must not finalize commands;
- after healing, a lagging node appends local catch-up events only for signed
  finalized decisions with valid quorum evidence;
- if two finalized decisions claim the same `consensus_decision_id` or
  `idempotency_key`, verification fails and IO must reject any later duplicate
  command envelope;
- local ledger sequence numbers are node-local and must not be compared across
  nodes as global order.

### Verification

Add:

```text
mix eigenforge.ledger.verify
```

The task should:

1. Read one local core ledger in `sequence` order.
2. Recompute each payload hash.
3. Recompute each event hash.
4. Verify each `previous_event_hash` link.
5. Verify each HMAC signature.
6. Verify finalized action events have the expected V1/V2 consensus status.
7. Verify local sequence numbers are contiguous and node-local.
8. Verify catch-up events append to the local chain instead of reusing foreign
   sequence numbers or foreign event hashes as local event hashes.
9. Report the first broken sequence, hash, signature, append-only, or
   consensus reference.

## 12. Dashboard

V1 uses Phoenix LiveView only. Scenic is deferred.

The dashboard is read-only and should show:

- active IO mode, clearly indicating simulator mode when active;
- connection status;
- latest CO2 reading;
- latest humidity reading;
- latest temperature reading;
- fan state;
- latest reasoner outcome;
- latest policy decision;
- last command envelope;
- last after-action status;
- recent durable decision/action ledger events;
- recent raw IO fault/status events;
- stale sensor alert status.

The dashboard reads current state from live IO streams and durable history from
local SQLite-backed read models. It does not call Home Assistant, write core
SQLite ledgers, or issue commands in V1.

## 13. Test Rigs And Golden Traces

### Core Logic Test Rig

V1 needs a core logic test rig independent of Home Assistant, simulator
clients, and external IO. It feeds normalized snapshot fixtures directly into
the reasoner, capability, policy, command issuance, and after-action
interpretation path.

Initial coverage:

- CO2 inside nominal range returns `no_threshold_event`.
- CO2 above nominal maximum proposes fan on.
- CO2 below nominal minimum proposes fan off.
- CO2 above nominal maximum with fan already on records `propose_no_action`.
- CO2 below nominal minimum with fan already off records `propose_no_action`.
- Stale CO2 returns `insufficient_fresh_data` and denies action.
- Unknown/stale fan state allows idempotent fan on/off when CO2 requires it.
- Unknown/stale non-idempotent actuator state denies blind command.

### Simulator Acceptance Path

Simulator mode should support deterministic scenarios:

- CO2 above 1000 ppm produces fan-on proposal and command path.
- CO2 below 500 ppm produces fan-off proposal and command path.
- CO2 inside 500..1000 ppm produces no action.
- Stale sensor input produces a signed stale deny event and no command.
- Missing or invalid capability denies physical fan execution.
- Malformed sensor input records a durable fault/deny event where it affects
  decision safety and does not crash the pipeline.

Minimum simulator fixtures:

```text
config/simulator_snapshots/co2_high_fan_off.json
config/simulator_snapshots/co2_high_fan_on.json
config/simulator_snapshots/co2_low_fan_on.json
config/simulator_snapshots/co2_nominal_fan_off.json
config/simulator_snapshots/co2_stale_fan_off.json
config/simulator_snapshots/co2_malformed.json
```

The first implementation targets are:

```text
config/simulator_snapshots/co2_high_fan_off.json
config/simulator_snapshots/co2_high_fan_on.json
config/simulator_snapshots/co2_stale_fan_off.json
```

### Golden Trace Runner

V1 should include a golden trace runner as an executable implementation
contract for the control loop. It should take a normalized snapshot fixture and
produce the complete expected V1 chain without depending on Home Assistant:

```text
normalized snapshot
  -> reasoner outcome
  -> capability result
  -> policy decision
  -> finalized decision/action
  -> local SQLite ledger event or events
  -> command envelope or no-command result
  -> simulated IO observation or IO fault/status event
  -> core-authored after-action event where applicable
  -> ledger verification
```

The runner should be available through Mix tasks such as:

```text
mix eigenforge.trace.run \
  --fixture config/simulator_snapshots/co2_high_fan_off.json \
  --out tmp/traces/co2_high_fan_off.json

mix eigenforge.trace.verify \
  --trace test/golden_traces/co2_high_fan_off.json
```

Golden trace JSON uses this top-level shape:

```json
{
  "trace_id": "...",
  "fixture": "...",
  "steps": [],
  "ledger_events": [],
  "command_envelopes": [],
  "delivery_receipts": [],
  "after_actions": [],
  "verification": {}
}
```

`eigenforge.trace.run` should emit:

- a human-readable step-by-step trace for development and review;
- machine-checkable canonical JSON suitable for golden trace fixtures;
- the ledger event sequence, hashes, signatures, and command envelope fields
  needed to verify the chain.

`eigenforge.trace.verify` should compare an actual trace against a committed
golden trace. It should fail on missing, reordered, or contradictory control
steps; invalid signatures or hash-chain links; command delivery before ledger
commit; unexpected IO execution; mailbox validation behavior; IO-authored
after-action truth; or any attempt to persist live sensor streams as durable
history.

The trace runner is not a second runtime path. It exercises the same core
reasoner, capability, policy, command issuance, ledger writing, command
delivery boundary, and after-action interpretation code used by V1 runtime
where practical. Adapter interaction is simulated only at the IO boundary.

The runner should make V2 migration straightforward: later traces can replace
the single core decision step with three ordered core proposals, 2-of-3 voting,
a rotating finalizer, and one final command envelope while preserving the same
fixture-to-local-ledger verification shape.

### Golden Trace Acceptance Tests

Golden traces use static normalized snapshot fixtures and do not depend on
Home Assistant.

1. CO2 high turns fan on.

```text
snapshot: co2_ppm=1200, fan_state=off, freshness=fresh
reasoner outcome: propose_action fan on
capability check: allow
policy decision: allow
ledger: finalized command envelope persisted locally
IO command: delivered after local ledger commit
after-action: confirmed_changed observed_state=on
```

2. CO2 high but fan already on records no-action.

```text
snapshot: co2_ppm=1200, fan_state=on, freshness=fresh
reasoner outcome: propose_no_action
ledger: finalized no-action decision recorded locally
IO command: not delivered
```

3. Stale CO2 denies action.

```text
snapshot: co2_ppm=1200, fan_state=off, freshness=stale
reasoner outcome: insufficient_fresh_data
policy decision: deny_stale_snapshot
ledger: finalized stale deny decision recorded locally
IO command: not delivered
```

4. Ledger persistence failure returns an error and does not deliver.

```text
snapshot: co2_ppm=1200, fan_state=off, freshness=fresh
reasoner outcome: propose_action fan on
ledger: persistence attempted three times
result: {:error, :ledger_persistence_failed}
IO command: not delivered
```

### Initial Implementation Split

The first build slice includes:

```text
umbrella scaffolding
eigenforge_contracts
canonical JSON/hash/signature rules
PolicyDecision, CapabilityCheck, and DeliveryReceipt contracts
fixed ledger event types
signed genesis event
basic append-only local SQLite ledger with WAL mode and mutation rejection
triggers
reasoner
capability check
policy decision
command envelope
delivery receipt
golden trace runner/verifier
first three simulator fixtures
```

The following are deferred until after the simulator vertical slice:

```text
Home Assistant WebSocket reconnect behavior
Phoenix LiveView dashboard
multi-core ledger catch-up and quorum repair
production database operational hardening beyond local SQLite file
permissions and mutation triggers
node fault/restart events
IO debug log rotation
non-fan actuator stubs
```

## 14. Deferred V2/V3 Work

V2 adds three-core voting and quorum:

- three core nodes A/B/C;
- one local SQLite decision ledger per core node;
- ordered identical snapshots;
- 2-of-3 voting over normalized actions/no-actions;
- rotating finalizer;
- single command envelope issuance;
- IO execution at most once;
- quorum catch-up after node restart or network partition;
- fault-injection test rig that kills, restarts, delays, or partitions core
  nodes.

V2 persistence should move final command issuance to the rotating finalizer
after quorum. Each core node should sign its proposal/vote. After quorum, each
participating node persists the finalized consensus decision and supporting
vote references to its own local SQLite ledger. The finalizer must persist the
finalized decision locally before issuing the single command envelope. IO must
reject command envelopes that do not reference a finalized decision and quorum
evidence.

Network split behavior is part of the V2 acceptance bar:

- a 2-of-3 side can continue finalizing actions;
- a 1-of-3 side cannot finalize or command actuators;
- healed nodes append local catch-up evidence for signed finalized decisions
  before becoming eligible finalizers again;
- conflicting finalized records for the same `consensus_decision_id`,
  `correlation_id`, or `idempotency_key` fail verification.

V2/V3 should also revisit:

- quorum certificates and catch-up protocol details across multiple local
  ledgers;
- stronger immutable append-only storage options, including database-level
  immutability, external anchoring, WORM-style storage, or a specialized
  append-only event store;
- quorum signatures on command envelopes;
- application-level sensor/actuator signatures;
- separated keys or asymmetric cryptography;
- external ledger checkpoint anchoring;
- direct ESPHome adapters;
- InfluxDB read-only history/diagnostics access;
- LLM-backed reasoners;
- hysteresis, debounce, and dwell-time control;
- manual dashboard intents through the same capability, policy, ledger, and
  later quorum path.
