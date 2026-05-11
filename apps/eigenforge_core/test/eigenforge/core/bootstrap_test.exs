defmodule Eigenforge.Core.BootstrapTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CapabilityGrant
  alias Eigenforge.Contracts.DeviceInventory
  alias Eigenforge.Core.Bootstrap
  alias Eigenforge.Core.DetachedSignature
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.RuntimeConfig

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-bootstrap-#{System.unique_integer([:positive])}"
      )

    caps_dir = Path.join(dir, "capabilities")
    File.mkdir_p!(caps_dir)
    snapshots_dir = Path.join(dir, "snapshots")
    File.mkdir_p!(snapshots_dir)

    config = %RuntimeConfig{
      io_mode: :simulator,
      core_node_id: "core_a",
      core_db_path: Path.join(dir, "core.sqlite3"),
      hmac_secret: "bootstrap-secret",
      device_inventory_path: Path.join(dir, "devices.json"),
      device_inventory_sig_path: Path.join(dir, "devices.json.sig"),
      capability_grants_dir: caps_dir,
      simulator_snapshots_dir: snapshots_dir,
      after_action_timeout_ms: 3000,
      ha_reconnect_max_ms: 180_000,
      io_fault_status_log: Path.join(dir, "io_fault_status.log"),
      home_assistant: nil
    }

    write_signed_payload(
      config.device_inventory_path,
      config.device_inventory_sig_path,
      DeviceInventory.new!(%{
        rooms: [
          %{
            room_id: "placeholder",
            active: true,
            sensors: [%{"sensor_id" => "co2"}],
            actuators: [%{"actuator_id" => "vent_fan"}]
          }
        ]
      })
      |> Contracts.signable_map(),
      config.hmac_secret
    )

    write_signed_payload(
      Path.join(caps_dir, "fan.json"),
      Path.join(caps_dir, "fan.json.sig"),
      CapabilityGrant.new!(%{
        grant_id: "cap-core-rule-stub-fan",
        subject: "core_rule_stub",
        target: "actuator:fan",
        action: "command_actuator",
        scope: "room:placeholder",
        issued_at: "2026-05-08T12:00:00.000Z"
      })
      |> Contracts.signable_map(),
      config.hmac_secret
    )

    on_exit(fn -> File.rm_rf(dir) end)

    %{config: config}
  end

  test "bootstrap validates signed config and creates a compatible genesis ledger", %{
    config: config
  } do
    assert {:ok, %{active_room_id: "placeholder"}} = Bootstrap.validate(config)

    assert {:ok, rows} =
             LedgerSQLite.query_json(
               config.core_db_path,
               "SELECT event_type, sequence FROM ledger_events ORDER BY sequence ASC;"
             )

    assert rows == [%{"event_type" => "ledger_genesis", "sequence" => 1}]
  end

  test "bootstrap fails fast on unsupported signed config schema versions", %{config: config} do
    write_signed_payload(
      config.device_inventory_path,
      config.device_inventory_sig_path,
      DeviceInventory.new!(%{
        rooms: [
          %{
            room_id: "placeholder",
            active: true,
            sensors: [],
            actuators: []
          }
        ]
      })
      |> Contracts.signable_map()
      |> Map.put("schema_version", 2),
      config.hmac_secret
    )

    assert {:error, {:unsupported_schema_version, "eigenforge.device_inventory", 2}} =
             Bootstrap.validate(config)
  end

  test "bootstrap fails when an existing ledger contains unsupported durable payload versions", %{
    config: config
  } do
    assert {:ok, _} = Bootstrap.validate(config)
    assert {:ok, _} = LedgerSQLite.query(config.core_db_path, "DROP TRIGGER ledger_events_no_update;")
    assert {:ok, [%{"event_hash" => genesis_hash, "event_id" => genesis_event_id}]} =
             LedgerSQLite.query_json(
               config.core_db_path,
               "SELECT event_hash, event_id FROM ledger_events WHERE sequence = 1;"
             )

    bad_payload = %{
      "schema_id" => "eigenforge.reasoner_outcome",
      "schema_version" => 2,
      "format_version" => "json-canonical-v1",
      "reasoner_outcome_id" => "outcome-1",
      "reasoner_id" => "core_rule_stub",
      "reasoner_version" => "v1",
      "snapshot_id" => "snap-1",
      "snapshot_hash" => String.duplicate("a", 64),
      "outcome_type" => "propose_action",
      "target" => "actuator:fan",
      "requested_state" => "on",
      "reason" => "test",
      "confidence_bps" => 10000,
      "metadata" => %{}
    }

    bad_payload_json = Contracts.canonical_json(bad_payload)
    bad_payload_hash = Contracts.hash_canonical(bad_payload)

    assert {:ok, _} =
             LedgerSQLite.query(
               config.core_db_path,
               """
               INSERT INTO ledger_events (
                 sequence, event_id, event_type, core_node_id, consensus_decision_id,
                 consensus_status, quorum_ref, causation_id, correlation_id, subject,
                 source_app, occurred_at, observed_at, persisted_at, format_version,
                 schema_id, schema_version, payload, payload_hash, previous_event_hash,
                 event_hash, signature_version, signature
               ) VALUES (
                 2,
                 'event-2',
                 'reasoner_outcome_recorded',
                 'core_a',
                 'consensus-2',
                 'single_core_finalized',
                 '{}',
                 '#{genesis_event_id}',
                 'corr-2',
                 'core_rule_stub',
                 'eigenforge_core',
                 '2026-05-08T12:00:00.000Z',
                 '2026-05-08T12:00:00.000Z',
                 '2026-05-08T12:00:00.000Z',
                 'json-canonical-v1',
                 'eigenforge.ledger_event',
                 1,
                 #{sql_string(bad_payload_json)},
                 '#{bad_payload_hash}',
                 '#{genesis_hash}',
                 'hash-2',
                 'hmac-sha256-v1',
                 'sig-2'
               );
               """
             )

    assert {:error, {:bad_payload_schema, "eigenforge.reasoner_outcome", "eigenforge.reasoner_outcome", 2, "json-canonical-v1"}} =
             Bootstrap.validate(config)
  end

  test "bootstrap fails fast on invalid simulator fixtures in simulator mode", %{config: config} do
    File.mkdir_p!(config.simulator_snapshots_dir)

    bad_fixture =
      Path.join(config.simulator_snapshots_dir, "bad.json")

    File.write!(
      bad_fixture,
      ~s({"fixture_schema_id":"eigenforge.simulator_fixture","fixture_schema_version":2,"scenario_id":"bad-sim","snapshot_id":"snap-bad","snapshot_seq":1,"room_id":"placeholder","co2_ppm":1200,"fan_state":"off","source_entity_ids":{},"source_observation_ids":{},"source_observed_at":{},"source_received_seq":{},"source_received_monotonic_ms":{},"source_status":{},"normalized_at":"2026-05-08T12:00:00.000Z","freshness":"fresh"}) <> "\n"
    )

    assert {:error, {:invalid_fixture, ^bad_fixture, {:unsupported_fixture_schema_version, 2}}} =
             Bootstrap.validate(config)
  end

  defp write_signed_payload(payload_path, sig_path, payload, secret) do
    File.write!(payload_path, Contracts.canonical_json(payload) <> "\n")
    File.write!(sig_path, DetachedSignature.canonical_sidecar_json(payload, secret) <> "\n")
  end

  defp sql_string(value), do: "'#{String.replace(value, "'", "''")}'"
end
