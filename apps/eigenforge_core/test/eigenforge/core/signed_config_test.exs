defmodule Eigenforge.Core.SignedConfigTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CapabilityGrant
  alias Eigenforge.Contracts.DeviceInventory
  alias Eigenforge.Core.DetachedSignature
  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.SignedConfig

  setup do
    dir = Path.join(System.tmp_dir!(), "eigenforge-signed-config-#{System.unique_integer([:positive])}")
    caps_dir = Path.join(dir, "capabilities")
    File.mkdir_p!(caps_dir)

    on_exit(fn -> File.rm_rf(dir) end)

    config = %RuntimeConfig{
      io_mode: :simulator,
      core_node_id: "core_a",
      core_db_path: Path.join(dir, "core.sqlite3"),
      hmac_secret: "signed-config-secret",
      device_inventory_path: Path.join(dir, "devices.json"),
      device_inventory_sig_path: Path.join(dir, "devices.json.sig"),
      capability_grants_dir: caps_dir,
      after_action_timeout_ms: 3000,
      ha_reconnect_max_ms: 180_000,
      io_fault_status_log: Path.join(dir, "io_fault_status.log"),
      home_assistant: nil
    }

    %{dir: dir, caps_dir: caps_dir, config: config}
  end

  test "loads and verifies signed device inventory", %{config: config} do
    payload =
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
      |> Contracts.signable_map()

    write_signed_payload(config.device_inventory_path, config.device_inventory_sig_path, payload, config.hmac_secret)

    assert {:ok, loaded} = SignedConfig.load_device_inventory(config)
    assert loaded.inventory.rooms == payload["rooms"]
    assert loaded.active_room["room_id"] == "placeholder"
  end

  test "device inventory fails when sidecar signature is invalid", %{config: config} do
    payload =
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

    write_signed_payload(config.device_inventory_path, config.device_inventory_sig_path, payload, config.hmac_secret)

    tampered_sidecar =
      config.device_inventory_sig_path
      |> File.read!()
      |> Contracts.decode_json!()
      |> Map.put("signature", "bad-signature")
      |> Contracts.canonical_json()

    File.write!(config.device_inventory_sig_path, tampered_sidecar <> "\n")

    assert {:error, {:invalid_signature, _path}} = SignedConfig.load_device_inventory(config)
  end

  test "device inventory rejects unsupported schema version", %{config: config} do
    payload =
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
      |> Map.put("schema_version", 2)

    write_signed_payload(config.device_inventory_path, config.device_inventory_sig_path, payload, config.hmac_secret)

    assert {:error, {:unsupported_schema_version, "eigenforge.device_inventory", 2}} =
             SignedConfig.load_device_inventory(config)
  end

  test "capability grant rejects unsupported format version", %{config: config, caps_dir: caps_dir} do
    grant =
      CapabilityGrant.new!(%{
        grant_id: "cap-core-rule-stub-fan",
        subject: "core_rule_stub",
        target: "actuator:fan",
        action: "command_actuator",
        scope: "room:placeholder",
        issued_at: "2026-05-08T12:00:00.000Z"
      })
      |> Contracts.signable_map()
      |> Map.put("format_version", "json-canonical-v2")

    json_path = Path.join(caps_dir, "fan_v2.json")
    sig_path = json_path <> ".sig"
    write_signed_payload(json_path, sig_path, grant, config.hmac_secret)

    assert {:error, {:unsupported_format_version, "eigenforge.capability_grant", "json-canonical-v2"}} =
             SignedConfig.load_capability_grants(config)
  end

  test "loads signed capability grants into lookup map", %{config: config, caps_dir: caps_dir} do
    grant =
      CapabilityGrant.new!(%{
        grant_id: "cap-core-rule-stub-fan",
        subject: "core_rule_stub",
        target: "actuator:fan",
        action: "command_actuator",
        scope: "room:placeholder",
        issued_at: "2026-05-08T12:00:00.000Z"
      })
      |> Contracts.signable_map()

    json_path = Path.join(caps_dir, "fan.json")
    sig_path = json_path <> ".sig"
    write_signed_payload(json_path, sig_path, grant, config.hmac_secret)

    assert {:ok, lookup} = SignedConfig.load_capability_grants(config)

    assert %CapabilityGrant{} =
             lookup[{"core_rule_stub", "actuator:fan", "command_actuator", "room:placeholder"}]
  end

  defp write_signed_payload(payload_path, sig_path, payload, secret) do
    File.write!(payload_path, Contracts.canonical_json(payload) <> "\n")
    File.write!(sig_path, DetachedSignature.canonical_sidecar_json(payload, secret) <> "\n")
  end
end
