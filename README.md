# Eigenforge

Eigenforge is an Elixir/OTP-based reflective control layer for AI-era critical
infrastructure.

The long-term goal is a live, inspectable, capability-bounded control fabric
where AI cognition can participate in system operation without bypassing
explicit authority, policy, durable decision/action records, adapters, or later
quorum.

The current work has been narrowed into a first prototype spec:

- [PROTOTYPE-V1-SPEC.md](PROTOTYPE-V1-SPEC.md)
- [OS-SKETCH-9.md](OS-SKETCH-9.md)

## Current Prototype

V1 proves the input/output control loop before adding voting and quorum.

The prototype will use:

- Elixir/OTP on Linux/PREEMPT_RT or ordinary Linux for local development.
- An Elixir umbrella project.
- Home Assistant as the first device adapter.
- Home Assistant WebSocket events for sensor ingest.
- Home Assistant REST calls for fan execution.
- Postgres as the durable decision/action ledger.
- HMAC-SHA256 signatures for ledger events, command envelopes, device config,
  and capability grants.
- Schema-backed generated contract modules for control messages.
- Static signed capability grants loaded from config.
- Plain Elixir policy functions.
- A deterministic rule stub in place of AI inference.
- Phoenix as the first read-only dashboard.

The first actionable control rule is:

```text
if CO2 > 1000 ppm:
  propose fan on

if CO2 < 500 ppm:
  propose fan off

otherwise:
  no action
```

If the CO2 reading is stale, the system records a signed alert event and issues
no actuator command.

## Contract Schemas

V1 control messages are defined from checked-in JSON Schemas under
`priv/schemas`. Generated Elixir contract modules live under
`lib/eigenforge/contracts/generated` and share canonical JSON, hashing, and
HMAC helpers from `Eigenforge.Contracts`.

Regenerate contract modules with:

```text
elixir tools/generate_contracts.exs
```

## Prototype Architecture

The planned umbrella shape is:

```text
eigenforge_umbrella
  apps/eigenforge_mailbox
  apps/eigenforge_io
  apps/eigenforge_core
  apps/eigenforge_dashboard
```

Responsibilities:

- `eigenforge_mailbox`: dumb channel manager for routing, delivery, and read
  projections.
- `eigenforge_io`: passive Home Assistant/simulator ingest and command adapter.
- `eigenforge_core`: OODA loop, capabilities, policies, reasoner, ledger
  records, and command envelopes.
- `eigenforge_dashboard`: read-only Phoenix dashboard over live IO streams and
  durable decision/action history.

The IO boundary, core authority, mailbox boundary, durable ledger, and
dashboard are kept separate even though the first prototype runs locally.

## V1 Device Scope

V1 reads:

- CO2 sensor state from Home Assistant.

V1 can execute:

- fan on/off through Home Assistant.

V1 includes no-op stubs for:

- lights on/off;
- laser on/off;
- piezo beeper on/off or pulse.

The non-fan stubs return without physical action. Their safety limits and real
adapter behavior are future work.

## Local Configuration

Runtime secrets and Home Assistant entity IDs will live in a project-root
`.env` file ignored by git.

A committed `.env.example` should contain:

```text
HOME_ASSISTANT_URL=http://homeassistant.local:8123
HOME_ASSISTANT_TOKEN=replace_me
EIGENFORGE_HMAC_SECRET=replace_me
HA_CO2_ENTITY_ID=sensor.placeholder_co2
HA_FAN_ENTITY_ID=switch.placeholder_fan
```

The app should fail fast when required Home Assistant or signing configuration
is missing.

## Ledger And Capabilities

V1 treats durable decision/action history as part of the core prototype, not a
later add-on.

All persisted ledger events should be signed with HMAC-SHA256 and
hash-chained. Capability grants are also signed and loaded from config files at
startup.

The prototype should include a small Mix task or CLI helper to create signed
capability grant files, for example:

```text
mix eigenforge.capability.grant \
  --subject core_rule_stub \
  --target actuator:fan \
  --action command_actuator \
  --scope room:placeholder \
  --out config/capabilities/core_rule_stub_fan.json
```

## Dashboard

The V1 dashboard is Phoenix-only and read-only.

It should show:

- latest CO2 reading;
- fan state;
- Home Assistant connection status;
- last command envelope;
- latest policy and capability decision;
- recent durable decision/action ledger events;
- stale sensor alert status.

Manual dashboard commands are excluded from V1.

## Future Work

The following ideas remain part of the broader Eigenforge direction, but are
outside the first prototype.

### Voting And Quorum

Add three redundant core nodes:

- `core_a`
- `core_b`
- `core_c`

Each core should consume identical ordered snapshots, produce normalized
proposals, and require 2-of-3 agreement before issuing a command envelope. A
rotating finalizer should ensure at most one command envelope is issued for a
sequence.

### AI Cognition

Replace the deterministic rule stub with an LLM-backed reasoner. Different
nodes may produce different interpretations or proposed actions from the same
input; that stochastic variation is one reason the voting layer matters.

AI should remain capability-bound and policy-gated.

### More Adapters

Add direct ESPHome control, simulator adapters, cFS Software Bus integration,
custom embedded APIs, and hardware-in-the-loop test rigs.

Home Assistant is only the first convenient adapter, not Eigenforge authority.

### Native Dashboard

Add a Scenic native dashboard after the Phoenix state model and durable ledger
views are working.

### Manual Commands

Add dashboard-originated manual intents that pass through the same
capability, policy, durable ledger, command-envelope, and later voting path as
AI-originated actions.

### Stronger Cryptography

Move from local HMAC-SHA256 signatures to asymmetric signatures for capability
grants, ledger events, and eventually quorum-signed command envelopes.

### Capability OS Substrates

Keep the core object, capability, policy, voting, and durable ledger model
portable toward substrates such as Kry10, seL4, Genode, Nerves, CHERI-like
environments, or other capability-oriented runtimes.

### cFS Integration

Treat cFS as a possible lower-level static subsystem bus, not the identity of
Eigenforge. Eigenforge should own the principal model, capability model, policy
model, AI cognition loop, voting semantics, ledger schema, dashboard, and
adapter boundaries.

### Runtime Molding And Self-Modification

Longer-term Eigenforge goals include live introspection, runtime evolution,
versioned objects, generated code tracking, and non-stop operation where full
system reboots are rare.

These remain future design goals. They are intentionally excluded from V1.
