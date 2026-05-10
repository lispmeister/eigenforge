defmodule Eigenforge.Core.RuntimeConfigTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.RuntimeConfig

  @common_env %{
    "EIGENFORGE_IO_MODE" => "simulator",
    "EIGENFORGE_HMAC_SECRET" => "test-secret",
    "EIGENFORGE_CORE_NODE_ID" => "core_a",
    "EIGENFORGE_CORE_DB_PATH" => "var/core/core_a.sqlite3"
  }

  test "simulator mode does not require Home Assistant configuration" do
    assert {:ok, config} = RuntimeConfig.load(@common_env)

    assert config.io_mode == :simulator
    assert config.home_assistant == nil
    assert config.after_action_timeout_ms == 3000
    assert config.ha_reconnect_max_ms == 180_000
    assert config.device_inventory_path == "config/devices.json"
    assert config.device_inventory_sig_path == "config/devices.json.sig"
    assert config.capability_grants_dir == "config/capabilities"
    assert config.simulator_snapshots_dir == "config/simulator_snapshots"
  end

  test "home_assistant mode requires static Home Assistant values" do
    env = Map.put(@common_env, "EIGENFORGE_IO_MODE", "home_assistant")

    assert {:error, errors} = RuntimeConfig.load(env)

    assert {:missing_env, "HOME_ASSISTANT_URL"} in errors
    assert {:missing_env, "HOME_ASSISTANT_TOKEN"} in errors
    assert {:missing_env, "HA_CO2_ENTITY_ID"} in errors
    assert {:missing_env, "HA_FAN_ENTITY_ID"} in errors
  end

  test "home_assistant mode validates static entity id domains before connection" do
    env =
      @common_env
      |> Map.put("EIGENFORGE_IO_MODE", "home_assistant")
      |> Map.merge(%{
        "HOME_ASSISTANT_URL" => "http://homeassistant.local:8123",
        "HOME_ASSISTANT_TOKEN" => "token",
        "HA_CO2_ENTITY_ID" => "switch.not_a_sensor",
        "HA_HUMIDITY_ENTITY_ID" => "sensor.placeholder_humidity",
        "HA_TEMPERATURE_ENTITY_ID" => "sensor.placeholder_temperature",
        "HA_FAN_ENTITY_ID" => "sensor.not_a_switch"
      })

    assert {:error, errors} = RuntimeConfig.load(env)

    assert {:invalid_entity_domain, "HA_CO2_ENTITY_ID", "sensor.", "switch.not_a_sensor"} in errors

    assert {:invalid_entity_domain, "HA_FAN_ENTITY_ID", "switch.", "sensor.not_a_switch"} in errors
  end

  test "home_assistant mode accepts plausible static config" do
    env =
      @common_env
      |> Map.put("EIGENFORGE_IO_MODE", "home_assistant")
      |> Map.merge(%{
        "HOME_ASSISTANT_URL" => "http://homeassistant.local:8123",
        "HOME_ASSISTANT_TOKEN" => "token",
        "HA_CO2_ENTITY_ID" => "sensor.placeholder_co2",
        "HA_HUMIDITY_ENTITY_ID" => "sensor.placeholder_humidity",
        "HA_TEMPERATURE_ENTITY_ID" => "sensor.placeholder_temperature",
        "HA_FAN_ENTITY_ID" => "switch.placeholder_fan",
        "EIGENFORGE_AFTER_ACTION_TIMEOUT_MS" => "4500"
      })

    assert {:ok, config} = RuntimeConfig.load(env)

    assert config.io_mode == :home_assistant
    assert config.after_action_timeout_ms == 4500
    assert config.home_assistant.entity_ids.fan == "switch.placeholder_fan"
  end

  test "invalid mode fails startup validation" do
    env =
      @common_env
      |> Map.put("EIGENFORGE_IO_MODE", "mqtt")

    assert {:error, errors} = RuntimeConfig.load(env)

    assert {:invalid_io_mode, "mqtt"} in errors
  end

  test "invalid integer settings fail startup validation" do
    env = Map.put(@common_env, "EIGENFORGE_AFTER_ACTION_TIMEOUT_MS", "0")

    assert {:error, errors} = RuntimeConfig.load(env)

    assert {:invalid_positive_integer, "EIGENFORGE_AFTER_ACTION_TIMEOUT_MS", "0"} in errors
  end

  test "device inventory must contain exactly one active room" do
    assert {:ok, %{"room_id" => "one"}} =
             RuntimeConfig.validate_active_room(%{
               "rooms" => [
                 %{"room_id" => "one", "active" => true},
                 %{"room_id" => "two", "active" => false}
               ]
             })

    assert {:error, :no_active_room} =
             RuntimeConfig.validate_active_room(%{"rooms" => [%{"room_id" => "one"}]})

    assert {:error, {:multiple_active_rooms, 2}} =
             RuntimeConfig.validate_active_room(%{
               "rooms" => [
                 %{"room_id" => "one", "active" => true},
                 %{"room_id" => "two", "active" => true}
               ]
             })
  end
end
