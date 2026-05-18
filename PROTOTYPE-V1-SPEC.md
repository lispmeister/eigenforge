# Eigenforge Prototype V1 Implementation Spec

```text
spec_id: eigenforge.prototype_v1
spec_version: 1
status: implementation_spec
primary_layers:
  - intent
  - safety
  - requirements
  - architecture
  - contracts
  - verification
```

## Traceability Conventions

This spec uses stable IDs to make requirements, contracts, invariants, tests,
and future tickets traceable without replacing Markdown as the authoring
format.

```text
INTENT-V1-*     high-level goals
NON-GOAL-V1-*   explicitly excluded behavior
SLICE-V1-*      implementation slice/order constraints
REQ-V1-*        executable V1 requirements
SAFE-V1-*       safety/control constraints
COMP-V1-*       component contracts
AUTH-V1-*       payload authority classes
THREAT-V1-*     threat-model claims
CANON-V1-*      canonical JSON rules
SIGN-V1-*       signing rules
CONTRACT-V1-*   data/schema/signature contracts
OODA-V1-*       ordered control-loop steps
POLICY-V1-*     capability and policy rules
PROTO-V1-*      command/delivery protocol rules
RECOVERY-V1-*   restart/recovery rules
AA-V1-*         after-action authorship and ordering rules
LEDGER-V1-*     ledger integrity rules
VIEW-V1-*       dashboard/view contracts
TRACE-V1-*      golden trace acceptance cases
COMPAT-V1-*     V1 shapes preserved for V2
DEFERRED-V2-*   explicitly out-of-scope later work
```

IDs are normative labels for requirements already expressed in this document.
When an ID and surrounding prose conflict, the prose section containing the ID
is authoritative until the conflict is resolved in the same change.

## 1. Scope And Non-Goals

Traceability anchors:

```text
INTENT-V1-001: Prove a small, inspectable input/output control loop.
INTENT-V1-002: Preserve V2 multi-core voting and quorum compatibility.
INTENT-V1-003: Keep control facts auditable through contracts, signatures,
  golden traces, and a local append-only ledger.
SLICE-V1-001: Simulator-backed golden traces precede Home Assistant
  integration and dashboard work.
```

V1 proves the input/output control loop while keeping the data model compatible
with later multi-core voting and quorum. The goal is a small, inspectable
control path:

```text
outside world
  -> IO live observation
  -> core OODA loop
       -> reasoner (threshold evaluation)
       -> actuator-state gate (idempotency suppression)
       -> capability check
       -> policy decision
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

- **NON-GOAL-V1-001**: three-core voting or quorum;
- **NON-GOAL-V1-002**: LLM-backed reasoning;
- **NON-GOAL-V1-003**: manual dashboard commands;
- **NON-GOAL-V1-004**: hysteresis, debounce windows, or minimum actuator dwell
  time;
- **NON-GOAL-V1-005**: historical sensor charts from InfluxDB;
- **NON-GOAL-V1-006**: direct ESPHome control;
- **NON-GOAL-V1-007**: application-level signatures from sensors or actuators;
- **NON-GOAL-V1-008**: asymmetric cryptography or separated signing keys;
- **NON-GOAL-V1-009**: external ledger anchoring;
- **NON-GOAL-V1-010**: log rotation for IO debug files.

The V1 code should avoid shortcuts that make V2 quorum hard. V1 has one
effective core decision path and treats the single core as a one-member
consensus group, so the persistence boundary is the same shape as the later
post-quorum boundary.

### Implementation Order

Implementation starts with a simulator-backed golden trace vertical slice:

```text
simulator snapshot
  -> core reasoner
  -> actuator-state gate
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

Component contract summary:

| ID | Component | Owns | Inputs | Outputs | Must not |
| --- | --- | --- | --- | --- | --- |
| **COMP-V1-CONTRACTS** | `eigenforge_contracts` | Shared schemas, generated modules, canonical JSON, hashing, HMAC helpers | Checked-in JSON Schemas | Contract modules, hashes, signatures | Own runtime authority, IO, dashboard, mailbox delivery, or ledger writing |
| **COMP-V1-IO** | `eigenforge_io` | Outside-world boundary, normalization, adapter execution, IO fault/status stream | Home Assistant or simulator observations, command envelopes | Normalized snapshots, IO fault/status events, adapter attempts | Decide, evaluate policy, write core ledgers, or author after-action truth |
| **COMP-V1-CORE** | `eigenforge_core` | OODA loop, authority, finalization, local ledger, command issuance, after-action authorship | Live IO stream, IO fault/status stream, signed config | Ledger events, command envelopes, after-action events | Execute physical IO or bypass durable persistence before command delivery |
| **COMP-V1-MAILBOX** | `eigenforge_mailbox` | Mechanical delivery journal, routing, delivery receipts, projections | Committed command-envelope events | Delivery receipts, command publication, delivery projections | Authorize, mutate envelopes, validate policy, reinterpret command semantics |
| **COMP-V1-DASHBOARD** | `eigenforge_dashboard` | Read-only observability | Live streams and read models | LiveView display | Mutate system state, issue commands, call Home Assistant |

### App Responsibilities

`eigenforge_contracts` owns shared control-message contracts.

- Owns checked-in JSON Schemas for V1 contracts.
- Owns generated contract modules.
- Owns canonical JSON, hashing, HMAC signing, and verification helpers.
- Owns the contract generator and contract smoke/tests.
- Does not own runtime authority, IO, mailbox delivery, dashboard rendering, or
  durable ledger writing.

In the umbrella layout, the canonical schema source of truth is:

```text
apps/eigenforge_contracts/priv/schemas
```

References to `priv/schemas` in this document mean that app-level path unless
explicitly stated otherwise. Other apps must depend on `eigenforge_contracts`
for generated modules and shared verification helpers; they must not maintain
private copies of control-message schemas.

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
- Runs the reasoner, the actuator-state gate (`Core.ActuatorGate`), capability
  checks, and policy checks, in that order.
- Finalizes decisions through the configured consensus boundary.
- Persists finalized decision/action ledger records to the local SQLite ledger.
- Persists a finalized decision/action record before any command is sent to IO.
- Issues signed command envelopes after local ledger commit.
- Observes IO state/faults after command delivery and records after-action
  events.

`eigenforge_mailbox` is a mechanical delivery journal.

- Accepts, stores, routes, and delivers messages where applicable.
- Manages channels, topics, lightweight notifications, and supported read
  projections.
- Persists signed delivery receipts and minimal routing metadata needed for V1
  command redelivery/recovery.
- Maintains read projections only as mechanical read models over committed
  ledger records; projections do not grant authority or reinterpret events.
- Delivers command envelopes to IO through the mailbox boundary only after the
  corresponding local ledger commit.
- May read envelope identifiers required for routing, projection, and delivery
  receipts.
- Does not validate signatures, evaluate policy, decide authorization, change
  payload fields, enrich command semantics, or mutate message contents.
- Does not decide whether a command is allowed.

Mailbox persistence is limited to delivery mechanics. It may store command id,
decision event id, ledger sequence/hash, delivered topic, delivery timestamp,
receipt id, receipt signature, and delivery status. It must not store or
reinterpret policy state beyond identifiers already present in the command
envelope and receipt.

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

### V1 Invariants

These invariants are the authoritative set enforced by `mix eigenforge.ledger.verify`
and `mix eigenforge.trace.verify`. Failure messages cite invariant IDs.

- **INV-01** *(§9)*: No command envelope is delivered to IO before the corresponding
  `command_envelope_issued` ledger event is durably committed in the local SQLite
  ledger. In V2 IO-as-Judge mode: IO never executes without a quorum certificate
  attached to the after-action event.
- **INV-02** *(§9)*: IO executes at most one adapter action per `idempotency_key`.
  Duplicate deliveries of the same `idempotency_key` are rejected without adapter
  execution.
- **INV-03** *(§9)*: While any command is in-flight for a given `effect_key`, core
  issues no additional physical command for the same room, target, action, and
  requested state.
- **INV-04** *(§6.4)*: A given `snapshot_id` is processed at most once per core node.
  Replayed or duplicate PubSub deliveries with the same `snapshot_id` are ignored
  after the first completed or in-flight decision attempt.
- **INV-05** *(§7)*: A stale/deny decision for a given `(snapshot_id, correlation_id)`
  pair is recorded exactly once. No second component may independently write a
  duplicate `stale_snapshot_denied` event for the same pair.
- **INV-06** *(§10)*: After-action terminal status (`confirmed_changed`,
  `confirmed_already_in_state`, `adapter_rejected`, `adapter_failed`,
  `state_mismatch`, `timed_out`) is authored only by core, not by IO or mailbox.
- **INV-07** *(§11)*: The local ledger is append-only. No ledger row is updated,
  deleted, replaced, resequenced, or backfilled by runtime code. Only plain
  `INSERT` is permitted on `ledger_events`.
- **INV-08** *(§11)*: `sequence` values are contiguous, monotonically increasing,
  and node-local. Two events from the same node may not share a sequence number.
  Sequence numbers from different nodes must not be compared as global order.
- **INV-09** *(§11)*: `previous_event_hash` for sequence `N+1` equals the
  `event_hash` of sequence `N`. The genesis event (`sequence=1`) uses
  `previous_event_hash=eigenforge-ledger-genesis-v1`.
- **INV-10** *(§11)*: Every HMAC signature is verified using the correct purpose label
  (e.g., `eigenforge:v1:ledger_event`). Signatures produced with the wrong label
  are rejected.
- **INV-11** *(§11)*: Every decision-chain ledger event (`reasoner_outcome_recorded`,
  `capability_check_recorded`, `policy_decision_recorded`,
  `command_envelope_issued`, `after_action_recorded`, `stale_snapshot_denied`)
  carries a non-null `consensus_decision_id` and
  `consensus_status=single_core_finalized` in V1.
- **INV-12** *(§4)*: Secrets (`EIGENFORGE_HMAC_SECRET`, `HOME_ASSISTANT_TOKEN`, and
  any value loaded from a variable whose name contains `TOKEN`, `SECRET`,
  `PASSWORD`, or `KEY`) never appear in canonical payloads, golden traces, IO
  debug logs, dashboard output, test failure messages, or exception text. The
  redaction string is `[REDACTED]`.
- **INV-13** *(§4)*: Startup fails when any ledger payload, runtime config,
  signature sidecar, simulator fixture, or generated contract declares an
  unsupported `schema_id`, `schema_version`, or `format_version`.
- **INV-14** *(§9)*: Actuator observations can confirm or contradict a command only
  when IO-local receive ordering proves they arrived after command delivery
  (`source_received_seq.fan` or `source_received_monotonic_ms.fan` is greater
  than the value captured at delivery). Source wall-clock timestamps alone do not
  constitute proof of post-delivery ordering.

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
  Core.ActuatorGate
  Core.CapabilityChecker
  Core.PolicyEngine
  Core.CommandIssuer
  Core.AfterActionObserver

eigenforge_mailbox
  Mailbox.Supervisor
  Mailbox.ChannelManager
  Mailbox.CommandPublisher
  Mailbox.CommandTransport (behaviour; PubSubTransport is the V1 impl)
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

V1 startup behavior is mode-dependent:

| Failure class | `home_assistant` mode | `simulator` mode |
| --- | --- | --- |
| Missing or invalid `EIGENFORGE_HMAC_SECRET` | fail startup | fail startup |
| Missing or invalid required signed device inventory or capability config | fail startup | fail startup unless the artifact is an explicitly allowed unsigned simulator fixture |
| Missing required Home Assistant URL, token, or entity mapping | fail startup | ignored; simulator must not connect to Home Assistant |
| Invalid runtime mode value | fail startup | fail startup |
| Home Assistant unreachable after valid config loads | start degraded, publish connection status, retry | not applicable |
| Simulator fixture path missing or malformed | fail the simulator scenario or test that requested it | fail the simulator scenario or test that requested it |
| IO debug log path unwritable | start degraded and publish/log a local fault where possible | start degraded and publish/log a local fault where possible |
| Local core ledger hash/signature verification fails | fail startup | fail startup |
| Projection tables are missing or corrupt but ledger verifies | rebuild projections, then start | rebuild projections, then start |
| Mailbox receipt store is uninitialized on first startup | initialize signed store manifest, then start | initialize signed store manifest, then start |
| Previously initialized mailbox receipt store is missing, corrupt, or fails verification | start degraded and do not publish or redeliver commands until repaired | start degraded for runtime; fail the affected deterministic test |
| Unsupported checked-in schema or ledger payload version is encountered | fail startup | fail startup |

Runtime requirement anchors:

| ID | Requirement |
| --- | --- |
| **REQ-V1-RUNTIME-001** | Missing or invalid `EIGENFORGE_HMAC_SECRET` fails startup in every mode. |
| **REQ-V1-RUNTIME-002** | Missing or invalid signed device inventory or capability config fails startup unless the artifact is an explicitly allowed unsigned simulator fixture. |
| **REQ-V1-RUNTIME-003** | Simulator mode must not connect to Home Assistant or any other outside data source. |
| **REQ-V1-RUNTIME-004** | Home Assistant may start degraded only after otherwise valid configuration loads. |
| **REQ-V1-RUNTIME-005** | Local core ledger hash/signature verification failure fails startup. |
| **REQ-V1-RUNTIME-006** | Corrupt or missing projection tables with a valid ledger are rebuilt before start. |
| **REQ-V1-RUNTIME-007** | Unsupported checked-in schema or ledger payload versions fail startup. |

### Home Assistant Mode

Home Assistant mode uses:

- Home Assistant WebSocket API for sensor and actuator state ingest.
- Home Assistant REST API for fan command execution.

Home Assistant entity validation has static and dynamic phases:

- Static startup validation checks that required entity id environment
  variables are present, non-empty, and have plausible Home Assistant entity
  domains: CO2, humidity, and temperature mappings must use `sensor.*`; the fan
  mapping must use `switch.*` in V1.
- Dynamic validation runs after Home Assistant connects and verifies that the
  mapped entities exist and that the fan entity accepts `switch.turn_on` and
  `switch.turn_off`.
- Missing static mappings fail startup before any control loop begins.
  Wrong-class or missing entities discovered dynamically put Home Assistant IO
  into degraded/no-physical-control state until configuration is repaired.
  Core may continue processing simulator/test inputs, but Home Assistant mode
  must not issue physical commands before dynamic entity validation succeeds.

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
connection with deterministic capped exponential backoff:

```text
initial retry: 5 seconds
maximum retry: 3 minutes
config env: EIGENFORGE_HA_RECONNECT_MAX_MS=180000
```

Backoff attempts use:

```text
delay_ms = min(5000 * 2 ^ (attempt - 1), EIGENFORGE_HA_RECONNECT_MAX_MS)
```

The attempt counter starts at `1`, resets to `1` after a successful connection
that remains up long enough to publish `connection_up`, and uses monotonic time
while the process is running. V1 simulator and golden trace modes use no jitter.
Runtime Home Assistant mode may add bounded jitter only if tests can disable it
and the emitted connection-status records include the chosen delay.

Missing or invalid required configuration still fails startup.

Home Assistant REST service success means the service call was accepted by
Home Assistant. It is not proof that the actuator changed state and must never
produce `confirmed_changed` or `confirmed_already_in_state` by itself. Only
core-interpreted actuator observations or explicit adapter failure/rejection
evidence can terminate after-action.

Manual or external Home Assistant changes are treated as outside-world actuator
observations, not Eigenforge commands. A manual fan state change may update
live state, projections, and the next `effect_epoch`. It does not create a
command envelope, delivery receipt, policy decision, or after-action event by
itself. If a manual observation resolves an existing pending Eigenforge command
and its local receive ordering proves it arrived after command delivery, core
may use it as after-action evidence for that pending command. If the manual
observation contradicts the requested state, core records `state_mismatch`.
Source wall timestamps alone are not sufficient proof of post-delivery
ordering.

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

Unsigned simulator allowance is limited to static normalized snapshot fixtures
under `config/simulator_snapshots`. Device inventory, capability grants,
delivery receipts, command envelopes, durable ledger events, and after-action
events are signed in simulator mode. If tests need unsigned device or
capability fixtures, those fixtures must live under an explicit test-only path
and must not be accepted by normal runtime startup.

Simulator fixtures are unsigned but still schema-versioned. Each fixture must
include `fixture_schema_id`, `fixture_schema_version`, and a named scenario id.
Malformed fixture tests must intentionally declare the malformed field or
omission they are exercising so accidental JSON drift is not mistaken for an
accepted malformed-input scenario.

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

### V1 Threat Model

V1's signing, hashing, and redaction machinery defends against three
specific threats:

1. **Offline ledger tampering.** A signed, hash-chained ledger is detectable
   as modified if an attacker edits rows after the fact. `mix
   eigenforge.ledger.verify` catches breaks in the hash chain and invalid HMAC
   signatures.

2. **External audit without process trust.** A human auditor who does not
   trust the authoring process can independently recompute hashes and verify
   signatures using the shared HMAC secret (provided separately), confirming
   that ledger events were produced by a process holding that secret.

3. **Accidental credential leakage.** `EIGENFORGE_HMAC_SECRET`,
   `HOME_ASSISTANT_TOKEN`, and any variable whose name contains `TOKEN`,
   `SECRET`, `PASSWORD`, or `KEY` are redacted to `[REDACTED]` before
   appearing in canonical payloads, golden traces, IO debug logs, dashboard
   output, test failure messages, or exception text.

V1 does **not** defend against compromise of the process that holds
`EIGENFORGE_HMAC_SECRET` in memory. A compromised core process can forge
valid signatures and produce a plausible-but-fraudulent ledger. Key
separation, process isolation, hardware security modules, and asymmetric
cryptography are explicitly V2/V3 work (see §15).

Threat-model anchors:

```text
THREAT-V1-001: Offline ledger tampering is detectable through hash-chain and
  HMAC verification.
THREAT-V1-002: External audit can recompute hashes and verify signatures when
  the shared HMAC secret is provided separately.
THREAT-V1-003: Credential leakage is mitigated by mandatory redaction before
  canonical payloads, traces, logs, dashboard output, failures, or exceptions.
THREAT-V1-004: Process compromise of a holder of EIGENFORGE_HMAC_SECRET is out
  of scope for V1.
```

### Contract Payload Authority Classes

Every contract payload, signed or unsigned, must include:

```text
format_version
schema_id
schema_version
```

V1 validates contract payloads against checked-in JSON Schemas under:

```text
priv/schemas
```

At minimum, schemas must exist for:

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

V1 uses three payload authority classes:

- **AUTH-V1-001**: Unsigned contract payloads are schema-valid runtime or test messages that do
  not carry authority by themselves. Normalized snapshots, IO fault/status
  events, and unsigned simulator snapshot fixtures are in this class.
- **AUTH-V1-002**: Detached-signed payloads are schema-valid JSON files with a separate
  signature sidecar, such as runtime device inventory and capability grants.
- **AUTH-V1-003**: Ledger-contained durable payloads are schema-valid event payloads whose
  authority comes from the signed ledger event envelope that contains them.
  They do not need a second inner signature unless their own contract says so.

The verifier rejects any payload whose declared `schema_id` and
`schema_version` do not match a known local schema for its authority class.

V1 has no runtime schema migration. Startup fails if existing ledger payloads,
runtime config, signature sidecars, simulator fixtures, or generated contracts
declare an unsupported `schema_id`, `schema_version`, or `format_version`.
Forward/backward migrations require an explicit later migration tool and are
not attempted automatically.

A no-op migration tool stub reserves the migration interface and makes
accidental schema drift fail loudly:

```text
mix eigenforge.ledger.migrate --from 1 --to 1
```

In V1, this task asserts that every ledger payload has `schema_version=1` and
exits 0. For any other `--to` value it exits non-zero with a clear
`no V1→VN migration defined` message. Do not use schema workarounds that
bypass this check; add a real migration task instead.

The prose contract and checked-in schemas must agree. When they conflict, fix
the schema and generated module in the same ticket that changes the prose, or
explicitly mark the prose as future work outside the V1 contract. A V1 field,
enum value, or required/optional distinction is not accepted until the schema,
generated module, and golden trace expectations use the same name.

### Contract Compiler

`priv/schemas` is the V1 source of truth for control message contracts. The
project must include a contract generator that reads checked-in JSON Schemas
and emits Elixir contract modules.

Generated contract modules must provide:

- struct fields and basic type metadata;
- required-field validation;
- canonical JSON encoding;
- payload hashing;
- HMAC signing and verification helpers;
- stable display/fixture maps for golden traces.

No V1 app may hand-roll message maps for signed or ledger-relevant
contracts. Core, IO, mailbox, dashboard, config signing, ledger writing, and
golden trace tooling should use generated contract modules where practical.

The initial contract modules must cover:

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

Contract registry:

| ID | Module | Schema |
| --- | --- | --- |
| **CONTRACT-V1-DEVICE-INVENTORY** | `Eigenforge.Contracts.DeviceInventory` | `device_inventory.schema.json` |
| **CONTRACT-V1-CAPABILITY-GRANT** | `Eigenforge.Contracts.CapabilityGrant` | `capability_grant.schema.json` |
| **CONTRACT-V1-CAPABILITY-CHECK** | `Eigenforge.Contracts.CapabilityCheck` | `capability_check.schema.json` |
| **CONTRACT-V1-POLICY-DECISION** | `Eigenforge.Contracts.PolicyDecision` | `policy_decision.schema.json` |
| **CONTRACT-V1-NORMALIZED-SNAPSHOT** | `Eigenforge.Contracts.NormalizedSnapshot` | `normalized_snapshot.schema.json` |
| **CONTRACT-V1-REASONER-OUTCOME** | `Eigenforge.Contracts.ReasonerOutcome` | `reasoner_outcome.schema.json` |
| **CONTRACT-V1-COMMAND-ENVELOPE** | `Eigenforge.Contracts.CommandEnvelope` | `command_envelope.schema.json` |
| **CONTRACT-V1-DELIVERY-RECEIPT** | `Eigenforge.Contracts.DeliveryReceipt` | `delivery_receipt.schema.json` |
| **CONTRACT-V1-AFTER-ACTION** | `Eigenforge.Contracts.AfterActionEvent` | `after_action_event.schema.json` |
| **CONTRACT-V1-IO-FAULT-STATUS** | `Eigenforge.Contracts.IoFaultStatusEvent` | `io_fault_status_event.schema.json` |
| **CONTRACT-V1-LEDGER-EVENT** | `Eigenforge.Contracts.LedgerEvent` | `ledger_event.schema.json` |

This establishes a V1 control message ABI:

```text
schema -> generated contract module -> canonical JSON -> signature/hash -> golden trace
```

### Canonical JSON And Signing

V1 uses canonical JSON for signatures and hashes.

Canonicalization rules:

- **CANON-V1-001**: encode as UTF-8 JSON;
- **CANON-V1-002**: object keys must be strings;
- **CANON-V1-003**: sort object keys lexicographically;
- **CANON-V1-004**: emit no insignificant whitespace;
- **CANON-V1-005**: use normal JSON string escaping;
- **CANON-V1-006**: do not escape `/`;
- **CANON-V1-007**: reject duplicate object keys before canonicalization;
- **CANON-V1-008**: preserve array order exactly as supplied by the contract;
- **CANON-V1-009**: preserve `null` only for schema-declared nullable fields;
- **CANON-V1-010**: preserve integers as integers;
- **CANON-V1-011**: reject integers outside signed 64-bit range in V1 signed payloads;
- **CANON-V1-012**: avoid floats in signed payloads where possible;
- **CANON-V1-013**: represent fractional values as scaled integers or strings when they need to
  be signed;
- **CANON-V1-014**: represent timestamps as ISO-8601 UTC strings with millisecond precision;
- **CANON-V1-015**: preserve Unicode code points as supplied; V1 does not perform Unicode
  normalization before signing, so producers must emit a stable normalized form
  for any human-authored strings they sign;
- **CANON-V1-016**: exclude detached signature sidecars from the payload they sign;
- **SIGN-V1-001**: for command envelopes, `payload_hash` covers the command body excluding
  `payload_hash` and `signature`;
- **SIGN-V1-002**: for command envelopes, `signature` covers the command body including
  `payload_hash` but excluding `signature`;
- **SIGN-V1-003**: for delivery receipts, `signature` covers the receipt body excluding
  `signature`; delivery receipts do not carry a separate `payload_hash` in V1;
- **SIGN-V1-004**: for ledger events, `payload_hash` covers `payload` only;
- **SIGN-V1-005**: for ledger events, `event_hash` covers the ledger envelope excluding
  `event_hash` and `signature`;
- **SIGN-V1-006**: for ledger events, `signature` covers the ledger envelope including
  `event_hash` but excluding `signature`;
- **SIGN-V1-007**: for detached config sidecars, `payload_hash` covers the config payload;
- **SIGN-V1-008**: for detached config sidecars, `signature` covers the sidecar body including
  `payload_hash` and `signature_version`, excluding `signature`.

Use the same canonicalization implementation for config signing, capability
grant signing, command envelope signing, ledger writing, and ledger
verification.

The V1 canonical JSON profile is intentionally narrower than general JSON. Any
payload that requires duplicate-key repair, float rounding, integer widening,
or Unicode normalization is rejected before signing or verification.

HMAC signatures include explicit purpose/domain separation even though V1 uses
one shared secret. The bytes signed are:

```text
purpose "\n" canonical-json-body
```

V1 purpose labels:

```text
eigenforge:v1:config_sidecar
eigenforge:v1:capability_grant
eigenforge:v1:command_envelope
eigenforge:v1:delivery_receipt
eigenforge:v1:ledger_event
```

Verifiers reject signatures made with the wrong purpose label.

Canonical V1 timestamps use exactly this shape:

```text
2026-05-10T12:34:56.789Z
```

Requirements:

- UTC only, with a literal trailing `Z`;
- exactly three fractional second digits;
- zero-padded date and time fields;
- no timezone offsets such as `+00:00`;
- no missing milliseconds;
- no microsecond or nanosecond precision in signed payloads.

Golden trace mode must use deterministic clocks supplied by the trace runner.
Runtime mode may use the system clock, but serializers must still emit the same
canonical format.

Runtime duration checks use monotonic time, not wall-clock deltas. Command
expiry, source freshness age, reconnect backoff, and after-action timeouts are
measured with monotonic time captured alongside the wall-clock UTC timestamp
used for signed records. If wall-clock time jumps backward or forward, runtime
duration checks continue from monotonic measurements and emitted timestamps
resume canonical UTC formatting.

Monotonic clocks are process-local and do not survive restart. While a process
is running, elapsed-time checks use monotonic measurements. During startup and
recovery, core uses persisted canonical UTC deadlines such as `expires_at` and
the after-action deadline recorded or derivable from the command lifecycle. If
wall-clock evidence is missing, malformed, or appears to move backward relative
to the ledger tail, recovery must choose the conservative no-new-command path:
mark affected commands pending or timed out according to the durable deadlines,
and do not issue equivalent physical work until recovery records a terminal
after-action.

**Wall-clock skew recovery footgun.** The conservative path means that if the
system clock is adjusted backward by more than the remaining time on a pending
command's `expires_at` deadline at the moment of restart, recovery will mark
that command `timed_out` even if the command physically succeeded before the
restart. This is safe by design — an erroneous `timed_out` is less dangerous
than a duplicate command — but operators must be aware of it. Do not restart
the system during a known NTP correction or clock change that moves the clock
backward by more than a few seconds. A future `clock_skew_observed` ledger
event and explicit operator acknowledgment path could mitigate this; that work
is deferred to V2.

Secrets and credentials must never appear in canonical payloads, golden traces,
IO debug logs, dashboard output, test failure messages, or exception text. V1
redacts `HOME_ASSISTANT_TOKEN`, `EIGENFORGE_HMAC_SECRET`, and any value loaded
from variables whose names contain `TOKEN`, `SECRET`, `PASSWORD`, or `KEY`.
The redaction string is:

```text
[REDACTED]
```

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
signature. In simulator mode, the same signed runtime config is required;
unsigned allowance applies only to static simulator snapshot fixtures.

For V1, "unsigned test/demo config" means unsigned simulator snapshot fixtures
only. Normal runtime device inventory and capability grants remain signed in
both modes.

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

Domain and safety anchors:

| ID | Rule |
| --- | --- |
| **REQ-V1-DEVICE-001** | Runtime config must contain exactly one active room in V1. |
| **SAFE-V1-CO2-CONTROL** | CO2 is the only control-authoritative sensor input in V1. |
| **SAFE-V1-OBSERVE-ONLY** | Humidity and temperature are observe-only inputs in V1. |
| **SAFE-V1-CO2-MISSING** | Missing, malformed, unavailable, unknown, `not_yet_observed`, or stale CO2 denies physical fan commands. |
| **SAFE-V1-FAN-OFF** | Fan-off may be commanded only from fresh CO2 below the nominal minimum and after in-flight/restart recovery has resolved. |
| **SAFE-V1-IDEMPOTENT-FAN** | Unknown or stale fan state may permit fan on/off because the V1 fan actuator is idempotent. |
| **SAFE-V1-NON-IDEMPOTENT-BLIND** | Unknown or stale actuator state denies blind commands for non-idempotent actuators. |

V1 supports one room, but all contracts keep `room_id`.

Runtime config must contain exactly one active room in V1. Startup fails when
device inventory has zero active rooms or more than one active room. Later
versions may add multiple active rooms without changing the contract shape.
Rooms must declare `active` explicitly. In V1, exactly one room must set
`active: true`; inactive rooms may be present only as ignored future
configuration and must not be used for IO subscriptions, policy scope matching,
or command issuance.

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
      "active": true,
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

Fan-off is less safety-critical than fan-on. V1 may command fan off only from a
fresh CO2 observation below the nominal minimum and after in-flight/restart
recovery has resolved. It must not command fan off from stale, missing,
malformed, unavailable, unknown, or `not_yet_observed` CO2. V1 also never
commands fan on from missing CO2 by default. The fail-safe posture is
observe-and-deny on missing control input, not autonomous ventilation. Any later
"fail ventilating" behavior must be explicitly configured and specified before
implementation.

Only the fan has physical command execution in V1. Light, laser, and piezo
stubs may exist as adapter placeholders, but they return without physical
action.

Each sensor and actuator must record `transport_security`. Missing metadata
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

Each normalized snapshot must include:

```text
format_version
schema_id
schema_version
snapshot_id
snapshot_seq
snapshot_hash
room_id
co2_ppm
humidity_basis_points
temperature_millicelsius
fan_state
source_entity_ids
source_observation_ids
source_observed_at
source_received_seq
source_received_monotonic_ms
source_status
normalized_at
freshness
```

`snapshot_seq` is monotonically increasing per IO source and room. Home
Assistant mode assigns it per normalized room stream. Simulator trace mode
derives it from fixture order, starting at `1` for each trace unless the fixture
explicitly supplies a sequence.

`source_observation_ids` records the IO-assigned observation id for each source
that contributed to the snapshot, including `fan` when an actuator state
observation is available. `source_received_seq` records IO-local receive order
per source, and `source_received_monotonic_ms` records the process-local
monotonic receive tick used for freshness and ordering while the IO process is
running. Golden trace mode supplies deterministic receive sequence and
monotonic values.

`snapshot_hash` is the canonical JSON hash of the normalized snapshot body
excluding `snapshot_hash` itself and any detached signature fields. It includes
all source values, `source_entity_ids`, `source_observation_ids`,
`source_observed_at`, `source_received_seq`, `source_received_monotonic_ms`,
`source_status`, `normalized_at`, `snapshot_seq`, and `room_id`.

Signed normalized snapshots do not use floating point values. CO2 is an integer
ppm value. Humidity uses `humidity_basis_points`, where `5234` means 52.34
percent. Temperature uses `temperature_millicelsius`, where `21500` means
21.500 degrees Celsius. Display layers may render these as decimal values, but
signed contracts and golden traces use scaled integers.

`freshness` is either:

```text
fresh
stale
```

Top-level `freshness` is the control freshness for the CO2-driven fan rule. It
is `fresh` only when CO2 is present, parseable, available, and within the
configured stale window. Observe-only humidity or temperature staleness must be
represented in `source_status` but must not by itself set top-level
`freshness=stale`.

Freshness calculation:

- compute source age with monotonic timestamps captured when source events and
  normalized snapshots are observed;
- CO2 is stale when source age is greater than the configured stale window;
- CO2 is invalid when `source_observed_at.co2` is missing, malformed, or more
  than 2 seconds after `normalized_at`;
- invalid CO2 sets `source_status.co2` to the closest applicable value and
  top-level `freshness=stale`;
- future timestamps for observe-only sensors are represented in
  `source_status` and dashboard/fault context but do not block fan action.

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
not_yet_observed
```

Decision relevance:

- CO2 stale, missing, malformed, unavailable, or unknown means no physical
  command may be issued; core records a stale/deny/no-command path.
- Humidity and temperature are observe-only in V1. Their stale, missing,
  malformed, unavailable, or unknown status is shown as dashboard/fault context
  but does not itself deny fan action. These fields are present in V1 for
  dashboard realism and to exercise multi-source freshness plumbing; they carry
  no control authority and may be removed in a V1.x simplification if the
  contract surface needs reducing.
- Fan state stale or unknown still permits fan on/off commands because the fan
  actuator is idempotent. Non-idempotent actuators must not receive blind
  commands.

Decision-relevance matrix:

| Source | Status class | Control effect |
| --- | --- | --- |
| CO2 | `stale`, `missing`, `malformed`, `unavailable`, `unknown`, `not_yet_observed` | Deny physical command and record stale/deny/no-command path. |
| Humidity | `stale`, `missing`, `malformed`, `unavailable`, `unknown`, `not_yet_observed` | Observe-only dashboard/fault context; does not deny fan action by itself. |
| Temperature | `stale`, `missing`, `malformed`, `unavailable`, `unknown`, `not_yet_observed` | Observe-only dashboard/fault context; does not deny fan action by itself. |
| Fan | `stale`, `unknown`, `not_yet_observed` | Allows fan on/off only because the fan is idempotent; denies blind commands for non-idempotent actuators. |

Unknown, unavailable, malformed, or missing Home Assistant values should not
crash the pipeline. They should be represented as rejected live observations.
If they affect decision safety, core records the relevant durable
decision/action event after observing them.

Malformed input handling:

- A structurally invalid outside-world message that cannot be converted into a
  contract-valid normalized snapshot is rejected by IO and published only as an
  `IoFaultStatusEvent`.
- A malformed, missing, unavailable, or unknown CO2 value that can be
  represented in the normalized snapshot contract is published as a
  contract-valid safety snapshot with `co2_ppm=null`, the appropriate
  `source_status.co2`, and top-level `freshness=stale`; IO also publishes a
  fault/status event for operator visibility.
- Malformed, missing, unavailable, or unknown humidity or temperature is
  represented in `source_status` and may be accompanied by a fault/status
  event, but it does not block fan action.
- Malformed or unknown fan state is represented in `fan_state` and
  `source_status.fan`; it only blocks action for non-idempotent actuators.
- `not_yet_observed` is used at startup before a source has produced any
  observation. For CO2 it behaves like stale/missing and blocks physical
  commands.

### Decision Cadence And Snapshot Dedupe

Core runs the V1 OODA path for a room when it observes a normalized snapshot
whose `snapshot_id` has not already been processed by that core node. Replayed
or duplicate PubSub deliveries with the same `snapshot_id` are ignored after
the first completed or in-flight decision attempt.

If IO publishes a new `snapshot_id` with the same `snapshot_hash` as the latest
processed snapshot for that room, core may update live projections but does not
append a new decision-chain ledger event unless one of these is true:

- the previous decision attempt failed before reaching a final no-command or
  command-issued state;
- an in-flight command for the same room/target has resolved or timed out and
  the new snapshot still requires action;
- the snapshot changes a decision-relevant value, source status, or freshness;
- the system has restarted and recovery rules require recording a follow-up
  event.

Golden trace mode processes every fixture in order.

Runtime mode coalesces repeated nominal/no-threshold snapshots. It records a
new `reasoner_outcome_recorded` / `policy_decision_recorded` pair for a nominal
snapshot if and only if at least one of the following fields in
`latest_room_control_state` differs from the values recorded for the previous
committed decision for that room:

- `fan_state`
- `source_status.co2` (as stored in the projection)
- top-level `freshness`
- `pending_command_id` (non-null means a command is in flight)
- `connection_status`

If none of those fields differ, the nominal snapshot updates live projections
but does not append a new decision-chain ledger event. This predicate is
machine-checkable from projection state and avoids unbounded identical
no-action ledger growth.

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

The schema field name is `fault_type` in V1. Earlier names such as `status`,
`adapter_failed`, or `malformed_response` must be migrated to the enum above
before the schema is considered aligned with this spec.

Structurally invalid outside messages are not published as valid normalized
snapshots. When a malformed, unavailable, unknown, or missing value can be
represented in the normalized snapshot contract, IO may publish the
contract-valid safety snapshot described above and also emits an
`IoFaultStatusEvent` with `fault_type=malformed_observation` or the closest
applicable fault type. Core persists the fault only when it affects OODA or
decision context. Malformed or missing CO2 causes a stale/deny/no-command path.
Malformed humidity or temperature is dashboard/fault context only in V1.

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

Ordered OODA anchors:

```text
OODA-V1-001: Validate normalized snapshot shape, version, and decision
  relevance.
OODA-V1-002: Evaluate CO2 freshness and threshold state.
OODA-V1-003: Apply the fixed actuator-state gate after raw reasoner output.
OODA-V1-004: Check capability only when physical action remains proposed.
OODA-V1-005: Evaluate policy and produce a policy decision contract.
OODA-V1-006: Finalize and persist decision/action facts before delivery.
OODA-V1-007: Issue a signed command envelope only after durable local commit.
OODA-V1-008: Observe IO state/fault streams and record terminal after-action.
```

### Reasoner Interface

The reasoner is pluggable from the start. Core calls a reasoner
behavior/interface with a normalized snapshot and receives a normalized
reasoner outcome. V1 ships a deterministic rules reasoner; later versions can
add LLM reasoners without changing IO, policy, command envelope, or ledger
boundaries.

For V1, the deterministic rules reasoner owns CO2 threshold evaluation only.
It receives a normalized snapshot and returns a threshold-based outcome
(`propose_action`, `no_threshold_event`, or `insufficient_fresh_data`) without
consulting the current actuator state. Actuator-state suppression — the
"already in desired state" check — is the responsibility of the fixed
`Core.ActuatorGate` stage that immediately follows the reasoner (see
§7 Actuator-State Gate below).

This separation means any future reasoner (including LLM-backed reasoners)
produces raw threshold proposals; the gate applies the universal idempotency
suppression invariant without requiring each reasoner to reimplement it.
Core owns contract validation, event sequencing, capability checks, policy
checks, persistence, command issuance, and after-action observation.

Reasoner outcome types recorded in `reasoner_outcome_recorded` ledger events:

```text
propose_action          -- reasoner: CO2 threshold breached; no actuator-state check
propose_no_action       -- gate: threshold breached but actuator already in requested state
no_threshold_event      -- reasoner: CO2 within nominal range
insufficient_fresh_data -- reasoner: CO2 stale, missing, or malformed
```

The reasoner module itself only produces `propose_action`, `no_threshold_event`,
and `insufficient_fresh_data`. `Core.ActuatorGate` observes the raw reasoner
result and, when `propose_action` would be redundant (fan already in the
requested state for idempotent actuators), rewrites it to `propose_no_action`
before the outcome is recorded or passed to capability checking.

Reasoner output must include:

```text
reasoner_outcome_id
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

Example reasons (attribute to the stage that emits them):

```text
[reasoner] CO2 1240 ppm exceeds 1000 ppm threshold; propose vent fan ON.
[gate]     Threshold breach suppressed; fan actuator already in requested state ON.
[gate]     Threshold breach suppressed; fan actuator already in requested state OFF.
```

### Actuator-State Gate

`Core.ActuatorGate` is a fixed stage in the core OODA loop, positioned between
the reasoner and capability checking. It is not part of the reasoner behavior;
all reasoners pass through it.

When the reasoner returns `propose_action`, the gate evaluates the latest
actuator state from the normalized snapshot:

- If the fan is already in the requested state (fan state known and matches),
  the gate rewrites the outcome to `propose_no_action` with reason:
  `Threshold breach suppressed; fan actuator already in requested state ON/OFF.`
  Capability checking is skipped and no command envelope is issued.
- If fan state is unknown, stale, or `not_yet_observed` and CO2 requires
  action, the gate passes `propose_action` through unchanged because fan on/off
  is idempotent. Non-idempotent actuators must not receive blind commands;
  for those, unknown or stale state causes the gate to emit `propose_no_action`
  with reason `denied_unknown_non_idempotent_actuator_state`.

Actuator idempotency comes from the device inventory config field `idempotent`.

This no-action rule applies symmetrically to fan-on and fan-off. In V2, core
nodes vote on the gate's normalized `propose_no_action` outcome the same way
they vote on a physical action. V1 records the same normalized outcome shape in
`reasoner_outcome_recorded` ledger events.

### Timing Defaults

```text
snapshot stale after: 15 seconds
command envelope expires after: 5 seconds
after-action confirmation timeout: 3 seconds
```

`EIGENFORGE_AFTER_ACTION_TIMEOUT_MS` configures after-action timeout.

If CO2 is stale, core records a stale/deny decision and sends no actuator
command.

The stale CO2 path has exactly one ownership sequence:

1. IO publishes a contract-valid safety snapshot when possible.
2. Core validates shape and calls the reasoner.
3. The reasoner returns `outcome_type=insufficient_fresh_data`.
4. `Core.ActuatorGate` is skipped because no `propose_action` was returned.
5. Capability checking is skipped because no physical action is proposed.
6. Policy records `decision=deny_stale_snapshot`.
7. Core persists the required stale/no-command events and sends no command
   envelope.

No other component may independently write a second stale-deny decision for the
same snapshot and correlation id.

In V2 the OODA loop ends with a signed proposal sent to eigenforge_mailbox; the
consensus/finalization boundary now lives inside eigenforge_io.

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
no_command
deny_missing_capability
deny_invalid_capability
deny_stale_snapshot
deny_unknown_non_idempotent_actuator_state
deny_expired_command
deny_unsupported_action
noop_stub
```

Rate limiting is deferred. `deny_rate_limited` is not a V1 policy result,
schema enum, golden trace expectation, or acceptance criterion.

The "already in desired state" case is a reasoner `propose_no_action` outcome,
not a policy denial.

Policy decision anchors:

| ID | Reasoner/gate outcome | Capability check | Policy result |
| --- | --- | --- | --- |
| **POLICY-V1-001** | `no_threshold_event` | skipped | `no_command` |
| **POLICY-V1-002** | `insufficient_fresh_data` | skipped | `deny_stale_snapshot` |
| **POLICY-V1-003** | `propose_no_action` | skipped | `no_command` |
| **POLICY-V1-004** | `propose_action` with valid grant | `allow` | `allow` |
| **POLICY-V1-005** | `propose_action` with missing grant | `deny_missing_capability` | `deny_missing_capability` |
| **POLICY-V1-006** | `propose_action` with invalid grant | `deny_invalid_capability` | `deny_invalid_capability` |
| **POLICY-V1-007** | unsupported physical action | checked when applicable | `deny_unsupported_action` |
| **POLICY-V1-008** | physical action for stub-only actuator | checked when applicable | `noop_stub` |

Every policy decision persisted to the ledger must include the capability
grant, missing capability, or invalid capability that determined the result.
For stale/no-command and no-threshold paths where no physical command is
proposed, `capability_grant_id` may be `null` and `capability_status` must be
`not_checked`.

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

Allowed V1 `capability_status` values in policy decisions are:

```text
allow
deny_missing_capability
deny_invalid_capability
not_checked
```

## 9. Command Envelopes And Delivery

Protocol anchors:

```text
PROTO-V1-CMD: Command envelopes carry the complete signed command body and
  references to the durable decision chain.
PROTO-V1-IDEM: idempotency_key prevents one finalized command decision from
  executing more than once by IO.
PROTO-V1-EFFECT: effect_key suppresses duplicate unresolved physical work
  across different decisions.
PROTO-V1-MAILBOX: Mailbox stores signed delivery receipts durably before
  publishing commands and never authorizes or mutates command semantics.
PROTO-V1-IO-ACCEPT: IO verifies command envelope, delivery receipt, expiry,
  committed-decision evidence, and idempotency before adapter execution.
RECOVERY-V1-CMD: Restart recovery resolves or classifies pending command work
  before equivalent physical commands may be issued.
```

Every command sent to IO uses a signed command envelope:

```text
format_version
schema_id
schema_version
command_id
idempotency_key
effect_key
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

V1 `idempotency_key` derivation:

1. Build a canonical JSON object with exactly these fields:
   `format_version`, `core_node_id`, `room_id`, `subject`, `target`, `action`,
   `scope`, `requested_state`, `snapshot_id`, `snapshot_hash`,
   `reasoner_outcome_id`, `policy_decision_id`, and
   `consensus_decision_id`.
2. Encode it with V1 canonical JSON rules.
3. Compute SHA-256 over the encoded bytes.
4. Encode as lowercase hex and prefix with `idem:v1:`.

`issued_at`, `expires_at`, delivery metadata, ledger `sequence`, and
`event_hash` are excluded so retries of the same finalized decision keep the
same idempotency key. Different finalized decisions for the same room/action
must use different `consensus_decision_id` values and therefore produce
different idempotency keys.

`idempotency_key` is the decision retry key. It prevents one finalized command
decision from being executed more than once by IO.

V1 also uses an `effect_key` to suppress duplicate physical work across
different decisions while equivalent work is unresolved:

1. Build a canonical JSON object with `format_version`, `room_id`, `target`,
   `action`, `requested_state`, and `effect_epoch`.
2. `effect_epoch` is the latest resolved actuator state observation id for the
   target from `source_observation_ids.fan` when known, otherwise the latest
   command lifecycle terminal event id for that target, otherwise `startup`.
3. Encode with V1 canonical JSON rules.
4. Compute SHA-256 over the encoded bytes.
5. Encode as lowercase hex and prefix with `effect:v1:`.

Core keeps at most one in-flight command per `effect_key`. A command is
in-flight from the successful local commit of `command_envelope_issued` until
core records a terminal after-action status: `confirmed_changed`,
`confirmed_already_in_state`, `adapter_rejected`, `adapter_failed`,
`state_mismatch`, or `timed_out`. While an equivalent command is in flight,
core records no additional physical command for the same room, target, action,
and requested state. It may update projections to show the pending command.

`effect_key` is included in the command envelope and after-action payload. IO
uses `idempotency_key` for exact command replay rejection. Core uses
`effect_key` for in-flight physical-effect suppression.

Core must finalize and persist the corresponding decision/action ledger record
before any command is sent to IO. In V1, finalization is the one-member core
decision. In V2, finalization requires quorum evidence.

For an action path, V1 persists a policy decision event and then a
`command_envelope_issued` ledger event. The command envelope's
`decision_event_id` references the `command_envelope_issued` ledger event that
contains the signed command envelope payload. The envelope also carries
`policy_decision_id`, `reasoner_outcome_event_id`, and `capability_event_id` so
the full causal chain can be verified.

V1 command lifecycle states:

| State | Author | Durable source |
| --- | --- | --- |
| `issued` | core | `command_envelope_issued` ledger event after local commit |
| `receipt_stored` | mailbox | signed delivery receipt durably stored before publish |
| `publish_attempted` | mailbox | command publish was attempted after receipt storage |
| `delivered` | mailbox | signed delivery receipt plus publish attempt; reflected in projections, not authorization |
| `accepted_by_io` | IO | IO accepted envelope and receipt validation; may be an IO fault/status or projection update |
| `adapter_attempted` | IO | adapter attempt id appears in IO stream and after-action evidence |
| `confirmed` | core | `after_action_recorded` with `confirmed_changed` or `confirmed_already_in_state` |
| `failed` | core | `after_action_recorded` with `adapter_rejected`, `adapter_failed`, or `state_mismatch` |
| `timed_out` | core | `after_action_recorded` with `timed_out` |

Only core-authored after-action events make a command lifecycle terminal for
control purposes.

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

Command delivery to IO goes through the mailbox boundary after local ledger
commit. The delivery channel is abstracted behind a `Mailbox.CommandTransport`
behaviour:

```elixir
@callback publish_command(envelope :: map(), receipt :: map(), opts :: keyword()) ::
  {:ok, delivery_evidence :: map()} | {:error, reason :: term()}
```

V1 ships `Mailbox.PubSubTransport` as the implementation, publishing to an
explicit command topic:

```text
commands:io
```

Transport guarantees assumed by the spec: best-effort delivery within a single
BEAM node; no broker durability; no guaranteed ordering across restarts. The
receipt store, phase tracking, and redelivery logic (described below) supply the
durability and recovery guarantees that the transport itself does not provide. A
future implementation may replace `PubSubTransport` with a direct `GenServer`
call or an Oban-backed queue without changing the mailbox boundary contract.

The mailbox may read the command identifiers required to route the envelope and
create the delivery receipt. It must not validate signatures, evaluate policy,
authorize execution, change payload fields, enrich command semantics, or mutate
the command envelope.

V1 keeps delivery receipts in the mailbox-owned signed receipt store. The
mailbox receipt store is the durable delivery journal for command delivery
metadata, and core does not absorb that persistence boundary in V1. This keeps
mailbox recovery and redelivery mechanical while preserving the V2 delivery
routing boundary.

After the corresponding ledger event is committed, the mailbox attaches a
signed delivery receipt to command delivery. The receipt is mechanical delivery
metadata, not authorization.

Mailbox has a signed receipt store manifest. First startup initializes the
manifest and an empty receipt store. After a manifest has existed, a missing,
corrupt, or unverifiable receipt store is treated as data loss: mailbox starts
degraded and does not redeliver or publish commands until the store is repaired
or explicitly reset in simulator/test mode.

Mailbox stores each signed delivery receipt durably before publishing the
command to IO. The receipt store must also track delivery phase:

```text
receipt_stored
publish_attempted
io_accepted
```

Delivery phase is receipt-store metadata, not a field inside the immutable
signed receipt payload. Updating delivery phase must not rewrite a signed
receipt or change its `receipt_id`, signature, or canonical body.

If mailbox crashes after `receipt_stored` but before `publish_attempted`,
restart recovery must not treat the command as delivered to IO. It may publish
the same command envelope with the same `idempotency_key` and either the same
receipt or a replacement receipt that references the same committed ledger
event, provided the command envelope has not expired. If `publish_attempted`
exists but no `io_accepted`, core treats the command as pending delivery rather
than physically attempted; IO idempotency still protects against duplicate
execution if the original publish actually arrived.

On restart, mailbox verifies receipt signatures and rebuilds its delivery
projection from the receipt store and phase records.

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

If IO receives an expired command envelope, IO rejects it without adapter
execution, publishes `fault_type=command_expired`, and records no physical
adapter attempt. Core maps an expired command with no adapter attempt to a
durable `timed_out` after-action when it observes the fault or when recovery
detects the expired pending command. Expiry is not `adapter_rejected` because
the adapter was never asked to act.

IO does not connect directly to any core SQLite database in V1.

IO maintains a local durable command execution store keyed by
`idempotency_key`. The store records at least `command_id`, `effect_key`,
`target`, `requested_state`, adapter attempt id, execution status, and
recorded_at. It is IO-local diagnostic/control state, not core authority. IO
uses it to reject duplicate command execution after IO process restart.

The V1 committed-decision verification rule is:

- core signs and persists the `command_envelope_issued` ledger event;
- mailbox receives the committed ledger event id, sequence, hash, and command
  id from core after the SQLite commit returns successfully;
- mailbox signs a delivery receipt containing those fields without changing the
  command envelope, stores it durably with `delivery_phase=receipt_stored`,
  and records `publish_attempted` before or atomically with PubSub publish;
- IO verifies the command envelope signature, delivery receipt signature,
  matching command/decision ids, and the presence of a non-empty signed receipt
  `ledger_event_hash`;
- when IO accepts the command for adapter handling, mailbox or IO records
  `io_accepted` with local receive ordering evidence for after-action
  comparison;
- IO treats the shared HMAC signature on the delivery receipt as V1 evidence
  that mailbox observed a committed core event.

IO does not independently prove SQLite durability in V1. V2 replaces this
single-node trust rule with quorum evidence.

### Restart Recovery

On startup, core verifies the local ledger hash chain before processing new
snapshots. It then rebuilds projections and command lifecycle state from the
ledger and signed delivery receipts that are still available through mailbox
storage or test harness state.

V1 restart recovery matrix:

| ID | Last durable state before restart | Recovery behavior |
| --- | --- | --- |
| **RECOVERY-V1-CMD-001** | No `command_envelope_issued` for the decision | No command is delivered; future snapshots may produce a new decision. |
| **RECOVERY-V1-CMD-002** | `command_envelope_issued` committed, no delivery receipt found | Mark command `issued` and pending; mailbox may redeliver the same envelope with the same `idempotency_key` and a fresh receipt if the envelope has not expired. If expired, core records `timed_out` after-action and does not redeliver. |
| **RECOVERY-V1-CMD-003** | Delivery receipt exists with `receipt_stored` but no `publish_attempted` | Treat command as pending delivery, not physically attempted; mailbox may publish the same envelope with the same `idempotency_key` if it has not expired. If expired, core records `timed_out` and does not publish. |
| **RECOVERY-V1-CMD-004** | Delivery receipt exists with `publish_attempted` but no `io_accepted` and no after-action terminal event | Treat command as pending delivery/unknown IO acceptance; mailbox may redeliver if the envelope has not expired, and IO must reject duplicate execution by `idempotency_key` if the first publish arrived. |
| **RECOVERY-V1-CMD-005** | Delivery receipt exists with `io_accepted`, no after-action terminal event | Treat command as in-flight; IO must reject duplicate execution by `idempotency_key`; core waits for observed actuator state or timeout before allowing an equivalent new effect. |
| **RECOVERY-V1-CMD-006** | IO may have executed but core crashed before observing result | On restart, core waits for the next live actuator observation. If it confirms requested state before timeout, record `confirmed_changed` or `confirmed_already_in_state` according to the after-action rules. Otherwise record `timed_out`. |
| **RECOVERY-V1-CMD-007** | IO idempotency memory lost | IO rebuilds executed `idempotency_key` state from its local durable command execution store. If that store is unavailable or fails verification, IO starts degraded and rejects command execution until the store is repaired or explicitly reinitialized for simulator/test use. |
| **RECOVERY-V1-CMD-008** | Pending command timeout elapsed while node was down | Core records `timed_out` during recovery before processing new equivalent physical commands. |

No autonomous recovery command invariant: after restart, core must classify or
terminally resolve every pending command for a room/target/effect before it may
issue an equivalent new physical command. Recovery may record `timed_out`,
`state_mismatch`, or a confirming after-action from fresh post-delivery
observations, but it must not silently abandon pending work and command again.

### V2 IO-as-Judge Mode

In V2 IO-as-Judge mode, cores no longer emit command_envelopes. They emit
signed_proposal messages containing the normalized action/no-action,
idempotency_key, and vote signature. IO becomes the sole issuer of actuator
commands. IO collects proposals from all three cores, performs 2-of-3 majority
voting, and — upon reaching quorum — executes the actuator command at most once
using the idempotency_key. IO then publishes a single after-action event with
the quorum evidence attached. Each core appends a quorum_finalized ledger event
referencing the vote evidence after observing IO's after-action publication.

## 10. After-Action Observation

The ledger distinguishes the decision to act from what core observed after IO
attempted execution.

After-action status is detected and recorded by core, not authored by IO. IO
publishes live actuator state changes and IO fault/status events; core
interprets those observations and records after-action events.

After-action requirement anchors:

```text
AA-V1-001: Only core authors terminal after-action status.
AA-V1-002: IO publishes live actuator state and fault/status evidence; it does
  not author after-action truth.
AA-V1-003: An actuator observation may confirm or contradict a command only
  when IO-local receive ordering proves it arrived after command delivery.
AA-V1-004: Source wall-clock timestamps alone are insufficient confirmation
  evidence.
AA-V1-005: Durable after-action records use terminal statuses only.
```

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

After-action event payload must include:

```text
after_action_id
command_id
idempotency_key
effect_key
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
adapter_rejected
adapter_failed
state_mismatch
timed_out
```

For Home Assistant, IO should prefer observed fan state from the HA event
stream after the REST command. If no confirming state event arrives within the
configured timeout, core records `timed_out` based on observed live state and
IO fault/status events. Before timeout, projections may show the non-terminal
runtime lifecycle state `command_sent_but_unconfirmed`. IO execution errors
caught locally are published on the IO fault/status stream for core to observe
and record where relevant.

Actuator observation ordering:

- an actuator observation may confirm or contradict a command only when its
  IO-local receive ordering proves it arrived after command delivery; for
  Home Assistant observations this means `source_received_seq.fan` or
  `source_received_monotonic_ms.fan` is greater than the corresponding value
  captured when mailbox/IO accepted the command;
- `source_observed_at` is still preserved and may reject obvious replays, but
  source wall time alone must not be used as proof that an observation happened
  after delivery;
- if the adapter attempt timestamp is available, confirmation should prefer
  observations at or after that adapter attempt timestamp;
- observations received before delivery, or carrying source timestamps older
  than the delivery evidence, may update live state, but they do not terminate
  the command lifecycle;
- when Home Assistant replays old events after reconnect, IO must preserve the
  original source timestamp and local receive sequence so core can reject stale
  confirmation evidence without losing live-state visibility.

After-action status rules:

- `confirmed_changed`: pre-command fan state was known and different from the
  requested state, and a post-command observation confirms the requested state.
- `confirmed_already_in_state`: pre-command fan state was known and already
  matched the requested state, or the adapter reports a no-op because the
  target was already in the requested state.
- `command_sent_but_unconfirmed`: IO accepted and attempted the command, no
  adapter failure was observed, and the timeout window has not yet elapsed.
  This is projection/runtime lifecycle state only; durable after-action records
  use a terminal status.
- `adapter_rejected`: IO or the adapter rejected the command before attempting
  physical execution.
- `adapter_failed`: IO attempted physical execution and observed an adapter or
  transport failure.
- `state_mismatch`: a post-command actuator observation arrives before timeout
  and contradicts the requested state.
- `timed_out`: no confirming actuator observation or terminal adapter fault is
  observed before the configured timeout.

If pre-command fan state was unknown or stale and a later observation confirms
the requested state, V1 records `confirmed_changed` with metadata noting that
the pre-command state was unknown. It must not claim
`confirmed_already_in_state` unless the pre-command state or adapter result
proved that no physical change was needed.

## 11. Local Core Ledger And Integrity

Each core node has a local SQLite database that stores its durable
decision/action ledger. The ledger is not the sensor historian.

Ledger integrity anchors:

```text
LEDGER-V1-001: The local core ledger is the authoritative durable record of
  finalized V1 control facts.
LEDGER-V1-002: Runtime code appends ledger rows with plain INSERT only.
LEDGER-V1-003: Projection tables are derived read models and may be rebuilt
  from the ledger.
LEDGER-V1-004: Ledger verification recomputes payload hashes, event hashes,
  previous-event links, signatures, sequence continuity, and V1 consensus
  fields.
LEDGER-V1-005: Catch-up compatibility is append-only; V1 must not splice or
  rewrite local ledger history for future multi-core evidence.
```

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

`consensus_decision_id` and `consensus_status` are required for V1
decision-chain events: `reasoner_outcome_recorded`,
`capability_check_recorded`, `policy_decision_recorded`,
`command_envelope_issued`, `after_action_recorded`, and
`stale_snapshot_denied`. They may be `null` for `ledger_genesis`,
`connection_status_observed`, `io_fault_observed`, and `node_fault_observed`
unless those events are explicitly attached to a decision correlation.
`quorum_ref` is `{}` in V1.

`stale_snapshot_denied` uses the same `PolicyDecision` payload contract as
`policy_decision_recorded`. It carries the same required fields and schema:
`format_version`, `schema_id`, `schema_version`, `policy_decision_id`,
`snapshot_id`, `snapshot_hash`, `reasoner_outcome_id`, `subject`, `target`,
`action`, `scope`, `requested_state`, `decision`, `capability_grant_id`,
`capability_status`, `reason`, `decided_at`, and `metadata`. The `decision`
field is `deny_stale_snapshot`.

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

V1 event cardinality by control path:

| Path | Required durable events | Optional durable events |
| --- | --- | --- |
| Command issued | `reasoner_outcome_recorded`, `capability_check_recorded`, `policy_decision_recorded`, `command_envelope_issued`, `after_action_recorded` | `io_fault_observed` when command execution faults affect after-action interpretation |
| Threshold reached but already in desired fan state | `reasoner_outcome_recorded`, `policy_decision_recorded` with no command, no capability check | relevant `io_fault_observed` only if it affected the decision context |
| CO2 inside nominal range | first nominal snapshot after startup or transition records `reasoner_outcome_recorded`, `policy_decision_recorded` with `not_checked` capability status and no command | repeated identical nominal snapshots may be coalesced in runtime; golden traces record the fixture path deterministically |
| Stale/malformed/missing CO2 deny | `reasoner_outcome_recorded`, `policy_decision_recorded`, `stale_snapshot_denied` | `io_fault_observed` for the malformed/missing source observation |
| Observe-only sensor fault | no decision-chain event required | `io_fault_observed` only if core promotes it for OODA context or operator audit |
| Outside connection state transition | `connection_status_observed` | none |

The same source observation and correlation id must not produce duplicate
durable events of the same event type.

Operator-audit promotion is narrow in V1. Core may promote observe-only sensor
faults to `io_fault_observed` only when one of these is true:

- the fault coincides with a connection transition;
- the fault occurs during an active command lifecycle;
- the fault persists for at least the configured CO2 stale window;
- the fault is needed to explain a dashboard degraded state.

Otherwise observe-only humidity/temperature faults remain ephemeral dashboard
context and debug-log entries.

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
- every decision-chain event records a finalized `consensus_decision_id`;
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

Database constraints must support:

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

V1 retention is intentionally simple: local SQLite ledgers and IO debug logs
are unbounded and intended for local/demo scale. Log rotation, ledger
compaction, archival checkpoints, and retention policies are deferred. Operators
must not delete or truncate `ledger_events`; deleting debug logs only removes
non-authoritative diagnostic history.

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
humidity_basis_points
temperature_millicelsius
fan_state
io_mode
connection_status
latest_reasoner_outcome_id
latest_policy_decision_id
latest_command_id
latest_after_action_id
pending_command_id
pending_effect_key
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
effect_key
after_action_status
updated_at
```

Use local PubSub/process notifications only as wakeups for predefined
decision/action subscriptions and dashboard updates. Notifications should carry
lightweight identifiers such as `core_node_id`, `event_id`, `event_type`, or
projection names. Consumers re-read from the local SQLite ledger or projection
tables instead of treating notification payloads as authoritative history.

### Multi-Core Catch-Up And Network Splits

This section is V2 compatibility guidance, not V1 executable scope. V1 code
must preserve the V1 fields and persistence boundaries that make these rules
possible later, but V1 tickets must not implement quorum, catch-up, IO-as-judge
finalization, or split-brain repair unless a later spec promotes them into scope.

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
io_node_id
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
  nodes as global order;
- IO enforces the 2-of-3 rule: if fewer than two valid proposals arrive for a
  given `consensus_decision_id`, IO logs a fault and takes no action; cores
  remain proposers only and never issue actuator commands directly.

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
6. Verify decision-chain events carry `consensus_status=single_core_finalized`
   in V1. Events with `consensus_status=quorum_finalized` or other unrecognized
   values are accepted as structurally valid (hash chain and HMAC still verified)
   but emit a warning:
   `unsupported_consensus_status: <value> (V1 single-core only)`.
   This allows the forward-compat fixture in `test/golden_traces/v2_quorum_shape_compat.json`
   to pass without silently concealing the mismatch.
7. Verify local sequence numbers are contiguous and node-local.
8. Verify catch-up events append to the local chain instead of reusing foreign
   sequence numbers or foreign event hashes as local event hashes.
9. Report the first broken sequence, hash, signature, append-only, or
   consensus reference. Cite the relevant invariant ID (INV-01 through INV-14)
   in each error message.

Ledger verification coverage map:

| Invariant | Ledger rule | Verifier behavior | Acceptance coverage |
| --- | --- | --- | --- |
| **INV-01** | Command delivery follows durable local commit | Fail when command delivery appears before `command_envelope_issued` commit evidence | Golden trace command path and delivery-before-commit negative test |
| **INV-02** | IO executes at most once per `idempotency_key` | Fail or flag duplicate execution evidence for the same idempotency key | Duplicate idempotency fault-injection test |
| **INV-07** | Ledger is append-only | Reject update/delete/resequence evidence and verify hash chain continuity | SQLite trigger tests and tampered ledger test |
| **INV-08** | Local sequence values are contiguous and node-local | Report first missing, duplicate, or non-contiguous sequence | Ledger verifier sequence test |
| **INV-09** | `previous_event_hash` links to prior `event_hash` | Report first broken hash-chain link | Golden trace tamper test |
| **INV-10** | Purpose-separated HMAC signatures | Reject signatures made with the wrong purpose label | Wrong-purpose signature test |
| **INV-11** | Decision-chain events carry finalized consensus fields | Report missing V1 consensus fields; warn on structurally valid unsupported V2 status | V2-shape forward-compat fixture |
| **INV-13** | Unsupported schema or format versions fail | Reject unsupported versions at startup or verification boundary | Unsupported-version startup test |
| **INV-14** | After-action confirmation requires IO-local post-delivery ordering | Reject source wall-clock-only confirmation evidence | Old actuator observation replay test |

## 12. Dashboard

V1 uses Phoenix LiveView only. Scenic is deferred.

View contract:

```text
VIEW-V1-DASHBOARD
reads:
  - live IO stream
  - IO fault/status stream
  - latest_room_control_state
  - recent_control_chains
must_not:
  - call Home Assistant
  - write core SQLite ledgers
  - issue command envelopes
  - mutate system state
must_display:
  - active IO mode
  - connection status
  - latest CO2, humidity, and temperature readings
  - fan state
  - latest reasoner outcome and policy decision
  - latest command envelope and after-action status
  - recent durable ledger events
  - recent raw IO fault/status events
  - stale sensor alert status
```

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

Dashboard freshness/status display must distinguish:

```text
fresh
stale
unknown
missing
malformed
unavailable
not_yet_observed
pending_command
degraded
```

These labels are not interchangeable. `unknown` means a source exists but its
current value is not known. `missing` means the expected value was absent.
`malformed` means a value was present but could not be parsed into the contract.
`unavailable` means the upstream system explicitly reported unavailable.
`not_yet_observed` means the runtime has not received any observation for that
source since startup. `pending_command` means core has issued a command whose
after-action is not terminal. `degraded` means connectivity or logging is
recovering after valid startup. Simulator mode and degraded Home Assistant mode
must be visible without implying that the dashboard can authorize control.

## 13. Test Rigs And Golden Traces

### Core Logic Test Rig

V1 needs a core logic test rig independent of Home Assistant, simulator
clients, and external IO. It feeds normalized snapshot fixtures directly into
the reasoner, `Core.ActuatorGate`, capability, policy, command issuance, and
after-action interpretation path.

Initial coverage:

- CO2 inside nominal range returns `no_threshold_event`.
- CO2 above nominal maximum proposes fan on.
- CO2 below nominal minimum proposes fan off.
- CO2 above nominal maximum with fan already on records `propose_no_action`.
- CO2 below nominal minimum with fan already off records `propose_no_action`.
- Stale CO2 returns `insufficient_fresh_data` and denies action.
- Unknown/stale fan state allows idempotent fan on/off when CO2 requires it.
- Unknown/stale non-idempotent actuator state denies blind command.
- Repeated identical snapshots are deduped or coalesced according to decision
  cadence rules.
- Equivalent fan command is suppressed while a prior command is in flight.
- Restart recovery resolves pending commands before issuing equivalent new
  physical work.

### Simulator Acceptance Path

Simulator mode must support deterministic scenarios:

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

V1 must include a golden trace runner as an executable implementation
contract for the control loop. It should take a normalized snapshot fixture and
produce the complete expected V1 chain without depending on Home Assistant:

```text
normalized snapshot
  -> reasoner outcome (threshold evaluation only)
  -> actuator-state gate (idempotency suppression)
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

`eigenforge.trace.run` must emit:

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

Golden trace mode must be deterministic. The trace runner supplies:

- a fixed start timestamp and monotonic millisecond ticks for every emitted
  timestamp;
- deterministic ids for `trace_id`, `snapshot_id`, `reasoner_outcome_id`,
  `capability_check_id`, `policy_decision_id`, `consensus_decision_id`,
  `event_id`, `command_id`, `receipt_id`, `after_action_id`,
  `adapter_attempt_id`, and `correlation_id`;
- deterministic `snapshot_seq` values;
- deterministic command expiry derived from `issued_at`.

Runtime mode may use UUIDs or another collision-resistant id source, but golden
trace mode derives ids from stable inputs:

```text
<kind>:v1:<sha256 canonical-json(trace_id, fixture, path, kind, ordinal)>
```

The exact helper must live in shared test/trace code so trace generation and
trace verification agree.

The runner must make V2 migration straightforward: later traces can replace
the single core decision step with three ordered core proposals, IO-as-judge
2-of-3 voting, and one IO-executed command with quorum evidence attached,
while preserving the same fixture-to-local-ledger verification shape. The
fault-injection rig must prove that killing any single core still produces
correct actuator change and identical ledger entries on surviving nodes.

### Golden Trace Acceptance Tests

Golden traces use static normalized snapshot fixtures and do not depend on
Home Assistant.

1. CO2 high turns fan on.

```text
TRACE-V1-CO2-HIGH-FAN-OFF
covers:
  - INTENT-V1-001
  - OODA-V1-002
  - OODA-V1-004
  - OODA-V1-007
  - POLICY-V1-004
  - PROTO-V1-IDEM
  - PROTO-V1-MAILBOX
  - AA-V1-001
  - INV-01
  - INV-02
```

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
TRACE-V1-CO2-HIGH-FAN-ON
covers:
  - INTENT-V1-001
  - OODA-V1-002
  - OODA-V1-003
  - POLICY-V1-003
  - SAFE-V1-IDEMPOTENT-FAN
  - INV-03
```

```text
snapshot: co2_ppm=1200, fan_state=on, freshness=fresh
reasoner (raw):      propose_action fan on  [threshold only; no actuator-state check]
actuator-state gate: propose_no_action      [fan already in requested state ON]
policy decision:     no_command with capability_status=not_checked
ledger:              reasoner_outcome_recorded (propose_no_action), policy_decision_recorded
IO command:          not delivered
```

3. Stale CO2 denies action.

```text
TRACE-V1-CO2-STALE-FAN-OFF
covers:
  - SAFE-V1-CO2-MISSING
  - OODA-V1-002
  - POLICY-V1-002
  - INV-05
```

```text
snapshot: co2_ppm=1200, fan_state=off, freshness=stale
reasoner outcome: insufficient_fresh_data
capability check: skipped
policy decision: deny_stale_snapshot
ledger: reasoner outcome, policy decision, and stale deny event recorded locally
IO command: not delivered
```

4. Ledger persistence failure returns an error and does not deliver.

```text
TRACE-V1-LEDGER-PERSISTENCE-FAILURE
covers:
  - OODA-V1-006
  - OODA-V1-007
  - PROTO-V1-MAILBOX
  - INV-01
```

```text
snapshot: co2_ppm=1200, fan_state=off, freshness=fresh
reasoner outcome: propose_action fan on
ledger: persistence attempted three times
result: {:error, :ledger_persistence_failed}
IO command: not delivered
```

### V2-Shape Forward-Compat Golden Trace Fixture

The V1 field shapes (`consensus_decision_id`, `consensus_status`, `quorum_ref`,
and supporting vote references) are promised to leave V2 migration
straightforward. To verify this promise rather than merely assert it, commit a
hand-built fixture:

```text
COMPAT-V1-QUORUM-SHAPE: V1 ledger and command-event fields preserve the
  consensus identifiers and quorum reference shape needed by V2.
TRACE-V1-V2-QUORUM-SHAPE-COMPAT: The forward-compat fixture proves V1 reports
  structurally valid but unsupported quorum-finalized evidence with a warning.
```

```text
test/golden_traces/v2_quorum_shape_compat.json
```

This fixture contains a `command_envelope_issued` ledger event with
`consensus_status="quorum_finalized"`, non-empty `quorum_ref`, and supporting
vote references. `mix eigenforge.ledger.verify` must produce a deterministic
and documented outcome on this fixture. V1 behavior:

- Accept the shape with a logged warning: `unsupported_consensus_status:
  quorum_finalized (V1 single-core only)`, and report the chain as
  structurally valid but carrying an unrecognized consensus status.

Do not silently accept the shape without the warning. V2 code will remove the
warning when quorum evidence verification is implemented.

### V1 Acceptance Demo Script

Commit `docs/v1-demo.md` as a reproducible 5–10 minute walkthrough:

```text
1. mix eigenforge.ledger.genesis     (initialize a clean ledger)
2. iex -S mix                        (start umbrella in EIGENFORGE_IO_MODE=simulator)
3. Trigger co2_high_fan_off fixture  (observe fan-on chain in dashboard)
4. Inspect ledger event chain and issued command envelope
5. mix eigenforge.ledger.verify      (expect: chain valid, all invariants pass)
6. Trigger co2_stale_fan_off fixture (observe stale-deny chain and no command)
7. Trigger co2_high_fan_on fixture   (observe propose_no_action chain, gate active)
```

All seven steps must produce the documented output from a fresh checkout
without manual configuration beyond copying `.env.example`. A passing demo
script defines "essence captured" for V1.

### V1 Fault-Injection Mini-Slice

Before Home Assistant physical IO is considered safe enough for manual demos,
V1 must include focused failure tests for:

- local ledger write failure after three attempts;
- command envelope expiry;
- duplicate `idempotency_key`;
- duplicate in-flight `effect_key`;
- IO restart with persisted duplicate `idempotency_key`;
- IO restart with missing or unverifiable command execution store;
- first startup with no mailbox receipt store manifest;
- corrupt or unverifiable mailbox receipt store;
- mailbox crash after `receipt_stored` but before `publish_attempted`;
- mailbox crash after `publish_attempted` but before `io_accepted`;
- corrupt projections with valid ledger rebuild;
- invalid command signature;
- mismatched delivery receipt command or decision id;
- missing or non-empty-invalid receipt `ledger_event_hash`;
- old actuator observation replayed after command delivery;
- Home Assistant observation with misleading source wall time but older local
  receive ordering;
- manual Home Assistant fan change during a pending command;
- malformed or missing CO2 safety snapshot path;
- Home Assistant unreachable after otherwise valid configuration;
- wrong-class Home Assistant entity mapping;
- unsupported schema or ledger payload version at startup;
- IO debug log path unwritable;
- restart with a pending command before after-action terminal status;
- restart after wall-clock jump while a pending command has persisted UTC
  expiry or after-action deadline.

These tests do not need a full V2 partition/fault-injection rig. They can use
simulator adapters, local test doubles, and deterministic golden trace clocks.

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
OS/process permission hardening beyond SQLite mutation rejection triggers
node fault/restart events
IO debug log rotation
non-fan actuator stubs
```

## 14. Traceability Index

This index is a navigation aid for reviewers, implementers, agents, and future
verification tooling. It does not replace the detailed requirements above.

| Intent / constraint | Primary requirements | Contracts / protocols | Invariants | Acceptance coverage |
| --- | --- | --- | --- | --- |
| **INTENT-V1-001** inspectable control loop | `OODA-V1-*`, `POLICY-V1-*` | `CONTRACT-V1-*`, `PROTO-V1-CMD` | `INV-01`, `INV-02`, `INV-03`, `INV-06` | `TRACE-V1-CO2-HIGH-FAN-OFF`, `TRACE-V1-CO2-HIGH-FAN-ON` |
| **INTENT-V1-002** V2 compatibility | `COMPAT-V1-*` | `PROTO-V1-CMD`, `LEDGER-V1-*` | `INV-11` | `TRACE-V1-V2-QUORUM-SHAPE-COMPAT` |
| **SAFE-V1-CO2-MISSING** deny unsafe missing control input | `OODA-V1-002`, `POLICY-V1-002` | Normalized snapshot contract, policy decision contract | `INV-05` | `TRACE-V1-CO2-STALE-FAN-OFF` |
| **SAFE-V1-IDEMPOTENT-FAN** suppress redundant safe fan work | `OODA-V1-003`, `POLICY-V1-003` | Reasoner outcome contract | `INV-03` | `TRACE-V1-CO2-HIGH-FAN-ON` |
| **PROTO-V1-IDEM** execute once per finalized decision | `PROTO-V1-IO-ACCEPT`, `RECOVERY-V1-CMD-*` | Command envelope, delivery receipt, IO execution store | `INV-02` | Duplicate idempotency fault-injection test |
| **AA-V1-001** core-authored terminal after-action | `OODA-V1-008`, `AA-V1-*` | After-action event contract | `INV-06`, `INV-14` | After-action and replay fault-injection tests |
| **LEDGER-V1 integrity** append-only signed local ledger | `LEDGER-V1-*`, verifier requirements | Ledger event envelope, canonical JSON, HMAC signing | `INV-07`, `INV-08`, `INV-09`, `INV-10`, `INV-13` | Ledger verifier, tamper, and unsupported-version tests |
| **VIEW-V1-DASHBOARD** read-only observability | `VIEW-V1-DASHBOARD` | Projections and live stream contracts | Authority boundaries in `COMP-V1-DASHBOARD` | Dashboard acceptance and mode/status display checks |

## 15. Deferred V2/V3 Work

Deferred scope labels:

```text
COMPAT-V1-001: V1 keeps consensus_decision_id, consensus_status, and quorum_ref
  fields so V2 quorum evidence can attach without changing the ledger envelope.
COMPAT-V1-002: V1 keeps command and after-action causal references shaped for
  later signed proposals and quorum certificates.
DEFERRED-V2-001: Three-core voting and quorum are not implemented in V1.
DEFERRED-V2-002: IO-as-judge finalization is described for compatibility but
  not implemented in V1.
DEFERRED-V2-003: Multi-core catch-up and partition repair are not implemented
  in V1.
DEFERRED-V2-004: Application-level sensor/actuator signatures, asymmetric
  cryptography, external anchoring, and stronger immutable storage are deferred.
```

V2 adds three-core voting and quorum with IO as the judge:

- three core nodes A/B/C;
- one local SQLite decision ledger per core node;
- ordered identical snapshots;
- 2-of-3 voting over normalized actions/no-actions;
- IO-as-judge (eigenforge_io performs 2-of-3 voting and executes);
- single actuator command issuance by IO upon reaching quorum;
- IO execution at most once per idempotency_key;
- quorum catch-up after node restart or network partition;
- fault-injection test rig that kills, restarts, delays, or partitions core
  nodes and proves correct actuator execution with identical ledger entries on
  surviving nodes.

V2 moves the finalization/judge boundary entirely into eigenforge_io. Cores
only emit signed proposals. IO performs 2-of-3 voting and executes directly.
Each core node signs its proposal/vote. IO collects proposals, verifies
signatures, and — upon reaching quorum — executes the actuator at most once
using the idempotency_key. IO then publishes a single after-action event with
quorum evidence. Each participating core node persists the finalized consensus
decision and supporting vote references to its own local SQLite ledger after
observing IO's quorum-finalized after-action event. IO must refuse execution
if fewer than two valid signed proposals arrive for a given
consensus_decision_id.

Network split behavior is part of the V2 acceptance bar:

- a 2-of-3 side can continue submitting proposals; IO can reach quorum and act;
- a 1-of-3 side cannot reach quorum; IO refuses to act without two valid
  proposals;
- healed nodes append local catch-up evidence for signed finalized decisions
  before resuming proposal submission;
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
