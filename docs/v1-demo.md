# Eigenforge V1 Demo

This is the shortest reproducible walkthrough for the V1 prototype.

Open two terminals from a clean checkout.

## 1. Initialize The Ledger

```bash
EIGENFORGE_IO_MODE=simulator \
EIGENFORGE_HMAC_SECRET=eigenforge-v1-test-secret \
mix eigenforge.ledger.genesis
```

Expected output: `:ok`.

## 2. Start The Umbrella

```bash
EIGENFORGE_IO_MODE=simulator \
EIGENFORGE_HMAC_SECRET=eigenforge-v1-test-secret \
iex -S mix
```

Expected output: the apps start and the simulator client begins publishing snapshots.

## 3. Push `co2_high_fan_off`

From the second terminal:

```bash
EIGENFORGE_IO_MODE=simulator \
EIGENFORGE_HMAC_SECRET=eigenforge-v1-test-secret \
mix run -e '
fixture =
  "config/simulator_snapshots/co2_high_fan_off.json"
  |> File.read!()
  |> Jason.decode!()

{:ok, %{snapshot: snapshot}} = Eigenforge.Core.SimulatorFixture.load(fixture)
Eigenforge.Core.PubSub.publish("io_state:room:placeholder", snapshot,
  registry_name: Eigenforge.Core.PubSub.Registry
)
'
```

Expected output: the dashboard shows a fan-on decision, and the ledger appends a
`command_envelope_issued` chain followed by `after_action_recorded`.

## 4. Inspect The Ledger Chain

```bash
EIGENFORGE_IO_MODE=simulator \
EIGENFORGE_HMAC_SECRET=eigenforge-v1-test-secret \
mix run -e '
{:ok, config} = Eigenforge.Core.RuntimeConfig.load()
{:ok, rows} = Eigenforge.Core.LedgerSQLite.query_json(
  config.core_db_path,
  "SELECT sequence, event_type FROM ledger_events ORDER BY sequence ASC;"
)
IO.inspect(rows)
'
```

Expected output: the chain includes `ledger_genesis`, `reasoner_outcome_recorded`,
`capability_check_recorded`, `policy_decision_recorded`,
`command_envelope_issued`, and `after_action_recorded`.

## 5. Verify The Ledger

```bash
EIGENFORGE_IO_MODE=simulator \
EIGENFORGE_HMAC_SECRET=eigenforge-v1-test-secret \
mix eigenforge.ledger.verify
```

Expected output: `:ok`.

## 6. Push `co2_stale_fan_off`

```bash
EIGENFORGE_IO_MODE=simulator \
EIGENFORGE_HMAC_SECRET=eigenforge-v1-test-secret \
mix run -e '
fixture =
  "config/simulator_snapshots/co2_stale_fan_off.json"
  |> File.read!()
  |> Jason.decode!()

{:ok, %{snapshot: snapshot}} = Eigenforge.Core.SimulatorFixture.load(fixture)
Eigenforge.Core.PubSub.publish("io_state:room:placeholder", snapshot,
  registry_name: Eigenforge.Core.PubSub.Registry
)
'
```

Expected output: the dashboard shows the stale-CO2 deny path, the ledger appends
`stale_snapshot_denied`, and no command envelope is issued.

## 7. Push `co2_high_fan_on`

```bash
EIGENFORGE_IO_MODE=simulator \
EIGENFORGE_HMAC_SECRET=eigenforge-v1-test-secret \
mix run -e '
fixture =
  "config/simulator_snapshots/co2_high_fan_on.json"
  |> File.read!()
  |> Jason.decode!()

{:ok, %{snapshot: snapshot}} = Eigenforge.Core.SimulatorFixture.load(fixture)
Eigenforge.Core.PubSub.publish("io_state:room:placeholder", snapshot,
  registry_name: Eigenforge.Core.PubSub.Registry
)
'
```

Expected output: the dashboard shows a no-action chain and the ledger records
`reasoner_outcome_recorded` plus `policy_decision_recorded`, with no command
envelope.
