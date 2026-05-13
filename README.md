![Elixir](https://img.shields.io/badge/Elixir-4B275F?logo=elixir&logoColor=white)
![OTP](https://img.shields.io/badge/OTP-8A2BE2?logo=erlang&logoColor=white)
![Build](https://github.com/lispmeister/eigenforge/actions/workflows/ci.yml/badge.svg)
![MIT License](https://img.shields.io/badge/License-MIT-yellow.svg)

![Eigenforge logo](docs/images/eigenforge-logo.jpg)

# Eigenforge

Eigenforge is an Elixir/OTP-based reflective control layer for AI-era critical
infrastructure.

The long-term goal is a live, inspectable, capability-bounded control fabric
where AI cognition can participate in system operation without bypassing
explicit authority, policy, durable decision/action records, adapters, or later
quorum.

## Build And Run

Build from the repository root:

```text
mix deps.get
mix compile
```

Run in simulator mode for local development:

```text
cp .env.example .env
mkdir -p var/eigenforge log
set -a
source .env
set +a

mix run --no-start -e 'endpoint_config = Application.get_env(:eigenforge_dashboard, Eigenforge.Dashboard.Endpoint, []); Application.put_env(:eigenforge_dashboard, Eigenforge.Dashboard.Endpoint, Keyword.merge(endpoint_config, http: [ip: {127, 0, 0, 1}, port: 4001], server: true)); {:ok, _} = Application.ensure_all_started(:eigenforge_io); {:ok, _} = Application.ensure_all_started(:eigenforge_dashboard); Process.sleep(:infinity)'
```

Open `http://localhost:4001` after the process reports that the dashboard is
running.

Run against Home Assistant by setting `EIGENFORGE_IO_MODE=home_assistant` in
`.env` and filling in the `HOME_ASSISTANT_*` and `HA_*_ENTITY_ID` values before
starting the same command.

The repository currently implements the V1 prototype slice described in:

- [PROTOTYPE-V1-SPEC.md](PROTOTYPE-V1-SPEC.md)
- [OS-SKETCH-9.md](OS-SKETCH-9.md)

## Current Prototype

V1 proves the input/output control loop before adding voting and quorum. The
current codebase includes the simulator-backed trace path, the Home Assistant
adapter, the local SQLite ledger, the mailbox receipt store, and the read-only
dashboard.

The prototype uses:

- Elixir/OTP on Linux/PREEMPT_RT or ordinary Linux for local development.
- An Elixir umbrella project with `contracts`, `mailbox`, `io`, `core`, and
  `dashboard` apps.
- Home Assistant as the first device adapter.
- Home Assistant WebSocket events for sensor ingest.
- Home Assistant REST calls for fan execution.
- Local SQLite as the durable decision/action ledger.
- HMAC-SHA256 signatures for ledger events, command envelopes, device config,
  and capability grants.
- Schema-backed generated contract modules for control messages.
- Static signed capability grants loaded from config.
- Plain Elixir policy functions.
- A deterministic rule stub in place of AI inference.
- Phoenix LiveView as the read-only dashboard.

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
`apps/eigenforge_contracts/priv/schemas`. Generated Elixir contract modules
live under `apps/eigenforge_contracts/lib/eigenforge/contracts/generated` and
share canonical JSON, hashing, and HMAC helpers from `Eigenforge.Contracts`.

Regenerate contract modules with:

```text
elixir tools/generate_contracts.exs
```

## Lab Journal

Engineering sessions can be recorded in the lab journal when explicitly
requested:

- [lab-journal/index.md](lab-journal/index.md)
- [lab-journal/TEMPLATE.md](lab-journal/TEMPLATE.md)

The workflow is adapted from
[lispmeister/lab-journal](https://github.com/lispmeister/lab-journal), a
structured engineering journal based on Kanare's laboratory notebook practices.
Canonical agent instructions live in [AGENTS.md](AGENTS.md). [CLAUDE.md](CLAUDE.md)
is a short compatibility pointer for Claude-oriented tooling.

## Prototype Architecture

The current umbrella shape is:

```text
eigenforge_umbrella
  apps/eigenforge_contracts
  apps/eigenforge_mailbox
  apps/eigenforge_io
  apps/eigenforge_core
  apps/eigenforge_dashboard
```

Responsibilities:

- `eigenforge_contracts`: checked-in schemas, generated contracts, canonical
  JSON, hashing, and HMAC helpers.
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
- Humidity and temperature sensor state as observe-only inputs.

V1 can execute:

- fan on/off through Home Assistant.

V1 includes no-op stubs for:

- lights on/off;
- laser on/off;
- piezo beeper on/off or pulse.

The non-fan stubs return without physical action. Their safety limits and real
adapter behavior are future work.

## Local Configuration

Runtime secrets and Home Assistant entity IDs live in a project-root `.env`
file ignored by git. A committed [.env.example](/Users/fix/projects/claude-code/eigenforge/.env.example)
contains the required simulator, Home Assistant, HMAC, ledger, and IO log
placeholders.

The app fails fast when required Home Assistant or signing configuration is
missing.

The repo also includes signed sample runtime config artifacts for local bring-up:

- [config/devices.json](/Users/fix/projects/claude-code/eigenforge/config/devices.json)
- [config/devices.json.sig](/Users/fix/projects/claude-code/eigenforge/config/devices.json.sig)
- [config/capabilities/core_rule_stub_fan.json](/Users/fix/projects/claude-code/eigenforge/config/capabilities/core_rule_stub_fan.json)
- [config/capabilities/core_rule_stub_fan.json.sig](/Users/fix/projects/claude-code/eigenforge/config/capabilities/core_rule_stub_fan.json.sig)

The committed signatures use the placeholder sample secret from `.env.example`
so they stay verifiable without committing a real secret.

The runtime now relies on local SQLite databases, not Postgres. The primary
decision/action ledger and mailbox receipt store are file-backed and intended
for local/demo scale.

## Ledger And Capabilities

V1 treats durable decision/action history as part of the core prototype, not a
later add-on.

All persisted ledger events are signed with HMAC-SHA256 and hash-chained.
Capability grants are also signed and loaded from config files at startup.

The repo includes Mix tasks to create signed capability grant files, for
example:

```text
mix eigenforge.capability.grant \
  --subject core_rule_stub \
  --target actuator:fan \
  --action command_actuator \
  --scope room:placeholder \
  --out config/capabilities/core_rule_stub_fan.json \
  --sig config/capabilities/core_rule_stub_fan.json.sig
```

Sign the committed sample device inventory with:

```text
mix eigenforge.config.sign \
  --in config/devices.json \
  --sig config/devices.json.sig
```

The signing helpers read `EIGENFORGE_HMAC_SECRET` from the environment or app
config, so replace the sample `replace_me` value before using the artifacts for
anything beyond local development.

## Dashboard

The V1 dashboard is Phoenix LiveView-only and read-only.

It shows:

- latest CO2 reading;
- fan state;
- Home Assistant connection status;
- last command envelope;
- latest policy and capability decision;
- recent durable decision/action ledger events;
- stale sensor alert status.

Manual dashboard commands are excluded from V1.

The dashboard reads from live PubSub streams and local SQLite-backed read
models only. It does not call Home Assistant or write to the ledger.

## Current Status

The V1 implementation set is complete in the repo. The only currently open
tracked work is a V2-only Phoenix dependency warning investigation.

## Future Work

The following ideas remain part of the broader Eigenforge direction, but are
outside V1.

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
