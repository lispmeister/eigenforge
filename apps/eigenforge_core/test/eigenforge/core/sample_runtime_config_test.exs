defmodule Eigenforge.Core.SampleRuntimeConfigTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.SignedConfig

  @repo_root Path.expand("../../../../..", __DIR__)

  test "committed sample signed config loads with the placeholder example secret" do
    config = %RuntimeConfig{
      io_mode: :simulator,
      core_node_id: "core_a",
      core_db_path: Path.join(System.tmp_dir!(), "sample-runtime-config.sqlite3"),
      hmac_secret: "replace_me",
      device_inventory_path: Path.join(@repo_root, "config/devices.json"),
      device_inventory_sig_path: Path.join(@repo_root, "config/devices.json.sig"),
      capability_grants_dir: Path.join(@repo_root, "config/capabilities"),
      after_action_timeout_ms: 3000,
      ha_reconnect_max_ms: 180_000,
      io_fault_status_log: Path.join(System.tmp_dir!(), "sample-runtime-config.log"),
      home_assistant: nil
    }

    assert {:ok, %{active_room: %{"room_id" => "placeholder"}}} =
             SignedConfig.load_device_inventory(config)

    assert {:ok, grants} = SignedConfig.load_capability_grants(config)

    assert Map.has_key?(
             grants,
             {"core_rule_stub", "actuator:fan", "command_actuator", "room:placeholder"}
           )
  end
end
