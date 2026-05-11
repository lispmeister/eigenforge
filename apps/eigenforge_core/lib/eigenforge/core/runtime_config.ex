defmodule Eigenforge.Core.RuntimeConfig do
  @moduledoc """
  Runtime configuration loader and startup validation for Eigenforge V1.

  This module validates only local configuration shape. It never connects to
  Home Assistant or any other outside service; dynamic adapter validation lives
  at the IO boundary after a connection exists.
  """

  @type mode :: :home_assistant | :simulator

  @type t :: %__MODULE__{
          io_mode: mode(),
          core_node_id: String.t(),
          core_db_path: String.t(),
          hmac_secret: String.t(),
          device_inventory_path: String.t(),
          device_inventory_sig_path: String.t(),
          capability_grants_dir: String.t(),
          simulator_snapshots_dir: String.t(),
          after_action_timeout_ms: pos_integer(),
          ha_reconnect_max_ms: pos_integer(),
          io_fault_status_log: String.t(),
          io_command_store_path: String.t(),
          home_assistant: map() | nil
        }

  defstruct [
    :io_mode,
    :core_node_id,
    :core_db_path,
    :hmac_secret,
    :device_inventory_path,
    :device_inventory_sig_path,
    :capability_grants_dir,
    :simulator_snapshots_dir,
    :after_action_timeout_ms,
    :ha_reconnect_max_ms,
    :io_fault_status_log,
    :io_command_store_path,
    :home_assistant
  ]

  @required_common ~w(EIGENFORGE_IO_MODE EIGENFORGE_HMAC_SECRET EIGENFORGE_CORE_NODE_ID EIGENFORGE_CORE_DB_PATH)
  @required_ha ~w(HOME_ASSISTANT_URL HOME_ASSISTANT_TOKEN HA_CO2_ENTITY_ID HA_HUMIDITY_ENTITY_ID HA_TEMPERATURE_ENTITY_ID HA_FAN_ENTITY_ID)

  @defaults %{
    "EIGENFORGE_AFTER_ACTION_TIMEOUT_MS" => "3000",
    "EIGENFORGE_HA_RECONNECT_MAX_MS" => "180000",
    "EIGENFORGE_IO_FAULT_STATUS_LOG" => "log/io_fault_status.log",
    "EIGENFORGE_IO_COMMAND_STORE_PATH" => "log/io_command_store.json",
    "EIGENFORGE_DEVICE_INVENTORY_PATH" => "config/devices.json",
    "EIGENFORGE_DEVICE_INVENTORY_SIG_PATH" => "config/devices.json.sig",
    "EIGENFORGE_CAPABILITY_GRANTS_DIR" => "config/capabilities",
    "EIGENFORGE_SIMULATOR_SNAPSHOTS_DIR" => "config/simulator_snapshots"
  }

  @doc """
  Loads runtime config from `System.get_env/0`.
  """
  @spec load() :: {:ok, t()} | {:error, [term()]}
  def load do
    env =
      Application.get_env(:eigenforge_core, :runtime_env, %{})
      |> stringify_env()
      |> Map.merge(System.get_env())

    load(env)
  end

  @doc """
  Loads and validates runtime config from a string-keyed env map.
  """
  @spec load(map()) :: {:ok, t()} | {:error, [term()]}
  def load(env) when is_map(env) do
    env = Map.merge(@defaults, stringify_env(env))
    common_errors = missing_errors(env, @required_common)

    with {:ok, mode} <- parse_mode(Map.get(env, "EIGENFORGE_IO_MODE")) do
      errors =
        common_errors ++
          mode_specific_errors(mode, env) ++
          integer_errors(env)

      case errors do
        [] -> build_config(mode, env)
        _ -> {:error, errors}
      end
    else
      {:error, error} -> {:error, common_errors ++ [error]}
    end
  end

  @doc """
  Validates the V1 exactly-one-active-room invariant.
  """
  @spec validate_active_room(map() | struct()) :: {:ok, map()} | {:error, term()}
  def validate_active_room(inventory) do
    rooms =
      inventory
      |> to_plain_map()
      |> fetch_value(:rooms)
      |> List.wrap()

    active_rooms =
      Enum.filter(rooms, fn room ->
        room
        |> to_plain_map()
        |> fetch_value(:active)
        |> Kernel.==(true)
      end)

    case active_rooms do
      [room] -> {:ok, to_plain_map(room)}
      [] -> {:error, :no_active_room}
      rooms -> {:error, {:multiple_active_rooms, length(rooms)}}
    end
  end

  defp build_config(:home_assistant = mode, env) do
    {:ok,
     %__MODULE__{
       io_mode: mode,
       core_node_id: env["EIGENFORGE_CORE_NODE_ID"],
       core_db_path: env["EIGENFORGE_CORE_DB_PATH"],
       hmac_secret: env["EIGENFORGE_HMAC_SECRET"],
       device_inventory_path: env["EIGENFORGE_DEVICE_INVENTORY_PATH"],
       device_inventory_sig_path: env["EIGENFORGE_DEVICE_INVENTORY_SIG_PATH"],
       capability_grants_dir: env["EIGENFORGE_CAPABILITY_GRANTS_DIR"],
       simulator_snapshots_dir: env["EIGENFORGE_SIMULATOR_SNAPSHOTS_DIR"],
       after_action_timeout_ms:
         parse_positive_integer!(env["EIGENFORGE_AFTER_ACTION_TIMEOUT_MS"]),
       ha_reconnect_max_ms: parse_positive_integer!(env["EIGENFORGE_HA_RECONNECT_MAX_MS"]),
       io_fault_status_log: env["EIGENFORGE_IO_FAULT_STATUS_LOG"],
       io_command_store_path: env["EIGENFORGE_IO_COMMAND_STORE_PATH"],
       home_assistant: %{
         url: env["HOME_ASSISTANT_URL"],
         token: env["HOME_ASSISTANT_TOKEN"],
         entity_ids: %{
           co2: env["HA_CO2_ENTITY_ID"],
           humidity: env["HA_HUMIDITY_ENTITY_ID"],
           temperature: env["HA_TEMPERATURE_ENTITY_ID"],
           fan: env["HA_FAN_ENTITY_ID"]
         }
       }
     }}
  end

  defp build_config(:simulator = mode, env) do
    {:ok,
     %__MODULE__{
       io_mode: mode,
       core_node_id: env["EIGENFORGE_CORE_NODE_ID"],
       core_db_path: env["EIGENFORGE_CORE_DB_PATH"],
       hmac_secret: env["EIGENFORGE_HMAC_SECRET"],
       device_inventory_path: env["EIGENFORGE_DEVICE_INVENTORY_PATH"],
       device_inventory_sig_path: env["EIGENFORGE_DEVICE_INVENTORY_SIG_PATH"],
       capability_grants_dir: env["EIGENFORGE_CAPABILITY_GRANTS_DIR"],
       simulator_snapshots_dir: env["EIGENFORGE_SIMULATOR_SNAPSHOTS_DIR"],
       after_action_timeout_ms:
         parse_positive_integer!(env["EIGENFORGE_AFTER_ACTION_TIMEOUT_MS"]),
       ha_reconnect_max_ms: parse_positive_integer!(env["EIGENFORGE_HA_RECONNECT_MAX_MS"]),
       io_fault_status_log: env["EIGENFORGE_IO_FAULT_STATUS_LOG"],
       io_command_store_path: env["EIGENFORGE_IO_COMMAND_STORE_PATH"],
       home_assistant: nil
     }}
  end

  defp mode_specific_errors(:home_assistant, env) do
    missing_errors(env, @required_ha) ++
      entity_domain_errors(env, [
        {"HA_CO2_ENTITY_ID", "sensor."},
        {"HA_HUMIDITY_ENTITY_ID", "sensor."},
        {"HA_TEMPERATURE_ENTITY_ID", "sensor."},
        {"HA_FAN_ENTITY_ID", "switch."}
      ])
  end

  defp mode_specific_errors(:simulator, _env), do: []

  defp missing_errors(env, vars) do
    vars
    |> Enum.filter(&blank?(Map.get(env, &1)))
    |> Enum.map(&{:missing_env, &1})
  end

  defp entity_domain_errors(env, checks) do
    checks
    |> Enum.reject(fn {var, _prefix} -> blank?(Map.get(env, var)) end)
    |> Enum.reject(fn {var, prefix} -> String.starts_with?(Map.fetch!(env, var), prefix) end)
    |> Enum.map(fn {var, prefix} -> {:invalid_entity_domain, var, prefix, Map.get(env, var)} end)
  end

  defp integer_errors(env) do
    ["EIGENFORGE_AFTER_ACTION_TIMEOUT_MS", "EIGENFORGE_HA_RECONNECT_MAX_MS"]
    |> Enum.reject(fn var -> positive_integer?(Map.get(env, var)) end)
    |> Enum.map(fn var -> {:invalid_positive_integer, var, Map.get(env, var)} end)
  end

  defp parse_mode("home_assistant"), do: {:ok, :home_assistant}
  defp parse_mode("simulator"), do: {:ok, :simulator}
  defp parse_mode(value), do: {:error, {:invalid_io_mode, value}}

  defp positive_integer?(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer > 0
      _ -> false
    end
  end

  defp positive_integer?(_value), do: false

  defp parse_positive_integer!(value) do
    {integer, ""} = Integer.parse(value)
    integer
  end

  defp blank?(value), do: value in [nil, ""]

  defp stringify_env(env) do
    Map.new(env, fn {key, value} -> {to_string(key), value} end)
  end

  defp fetch_value(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp to_plain_map(%_module{} = struct), do: Map.from_struct(struct)
  defp to_plain_map(map) when is_map(map), do: map
end
