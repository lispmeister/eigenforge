# Eigenforge Prototype V1 Spec

## Scope

V1 proves the input/output control loop before adding voting and quorum.

The first prototype covers:

- Home Assistant-backed sensor ingest.
- Normalized room snapshots.
- Signed, durable audit events in Postgres.
- Static signed capability grants loaded from config.
- Plain Elixir policy checks.
- A deterministic AI/rule stub.
- Command envelope issuance.
- IO adapter execution for the fan only.
- Phoenix read-only dashboard.

Voting and quorum are deferred to V2. The V1 architecture should still keep IO,
core authority, mailbox/audit, and dashboard concerns separated so the
three-core voting path can be added without collapsing boundaries.

## Project Shape

Use an Elixir umbrella project:

```text
eigenforge_umbrella
  apps/eigenforge_mailbox
  apps/eigenforge_io
  apps/eigenforge_core
  apps/eigenforge_dashboard
```

Responsibilities:

- `eigenforge_mailbox`: Postgres-backed audit/event log and event routing.
- `eigenforge_io`: Home Assistant WebSocket ingest and REST command adapter.
- `eigenforge_core`: capabilities, policies, rule stub, command envelopes.
- `eigenforge_dashboard`: Phoenix dashboard over the shared state/audit model.

## Local Configuration

Secrets and local Home Assistant configuration live in a project-root `.env`
file ignored by git.

Commit a `.env.example` with placeholders:

```text
HOME_ASSISTANT_URL=http://homeassistant.local:8123
HOME_ASSISTANT_TOKEN=replace_me
EIGENFORGE_HMAC_SECRET=replace_me
HA_CO2_ENTITY_ID=sensor.placeholder_co2
HA_FAN_ENTITY_ID=switch.placeholder_fan
```

The application should fail fast on startup if required Home Assistant values
or signing secrets are missing.

## Home Assistant Integration

Use the Home Assistant WebSocket API for event ingest:

```text
https://developers.home-assistant.io/docs/api/websocket/
```

Use the Home Assistant REST API for actuator execution:

```text
https://developers.home-assistant.io/docs/api/rest/
```

V1 actionable backend:

- CO2 sensor read from Home Assistant.
- Fan on/off through Home Assistant.

V1 actuator stubs:

- lights on/off
- laser on/off
- piezo beeper on/off or pulse

The non-fan stubs should return without physical action. They are placeholders
for later policy and adapter work.

## Control Rule

The V1 autonomous rule stub is deterministic:

```text
if CO2 > 1000 ppm:
  propose fan on

if CO2 < 500 ppm:
  propose fan off

otherwise:
  no action
```

AI/LLM cognition is stubbed out in V1. The rule stub should sit behind an
interface that can later be replaced by an LLM-backed reasoner.

## Freshness And Timing

Defaults:

```text
snapshot stale after: 15 seconds
command envelope expires after: 5 seconds
Home Assistant reconnect retry: 5 seconds
```

If the CO2 reading is stale:

- raise a signed alert event;
- issue no actuator command.

## Capability Grants

Capabilities are loaded from config files at startup.

Capability grants are signed from the start using the simplest local mechanism:

```text
HMAC-SHA256 with EIGENFORGE_HMAC_SECRET
```

Add a small Mix task or CLI helper to create signed capability grant files.

Example shape:

```text
mix eigenforge.capability.grant \
  --subject core_rule_stub \
  --target actuator:fan \
  --action command_actuator \
  --scope room:placeholder \
  --out config/capabilities/core_rule_stub_fan.json
```

The helper should:

1. Load `EIGENFORGE_HMAC_SECRET`.
2. Build a canonical capability grant payload.
3. Sign the payload with HMAC-SHA256.
4. Write the grant as JSON.
5. Allow startup verification before the grant is accepted.

## Policy

V1 policies are plain Elixir functions, not a DSL.

Initial policy behavior:

- allow fan on/off only when a valid signed capability grant exists;
- allow no physical execution for lights, laser, and beeper stubs;
- deny or no-op unsupported adapter actions;
- deny commands based on stale snapshots;
- record every policy decision as a signed audit event.

## Audit Log

Postgres is the durable mailbox/audit store.

All audit entries are signed using HMAC-SHA256 from the start.

V1 should persist signed audit events for:

- Home Assistant connection status.
- Sensor observations.
- Normalized snapshots.
- Stale sensor alerts.
- Capability checks.
- Policy decisions.
- Rule-stub proposals.
- Command envelopes.
- Adapter command attempts.
- Adapter results.
- Faults and restarts where practical.

The audit/event schema should preserve enough causal information to answer:

```text
why did the fan turn on/off?
which CO2 reading triggered it?
which capability allowed it?
which policy decision allowed or denied it?
which command envelope was issued?
what did the Home Assistant adapter report?
```

## Dashboard

V1 uses Phoenix only. Scenic is deferred.

The dashboard is read-only in V1. It does not need a manual fan on/off command.

Minimum dashboard state:

- latest CO2 reading;
- fan state;
- Home Assistant connection status;
- last command envelope;
- latest policy and capability decision;
- recent signed audit events;
- stale sensor alert status.

## Deferred To V2

V2 adds the three-core voting and quorum path:

- core nodes A/B/C;
- ordered identical snapshots;
- 2-of-3 voting over normalized actions;
- rotating finalizer;
- single command envelope issuance;
- IO execution at most once.

The V1 code should avoid shortcuts that make V2 hard, but V1 does not implement
quorum.
