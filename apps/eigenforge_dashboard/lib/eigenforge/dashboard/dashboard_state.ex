defmodule Eigenforge.Dashboard.DashboardState do
  @moduledoc """
  Read-only dashboard snapshot loader.
  """

  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.SignedConfig
  alias Eigenforge.Dashboard.ReadModel

  @spec load() :: {:ok, map()} | {:error, term()}
  def load do
    with {:ok, config} <- RuntimeConfig.load(),
         {:ok, %{active_room: %{"room_id" => room_id}}} <- SignedConfig.load_device_inventory(config),
         {:ok, snapshot} <-
           ReadModel.snapshot(config.core_db_path, room_id,
             redaction_secrets:
               [config.hmac_secret, config.home_assistant && config.home_assistant[:token]]
               |> Enum.reject(&(&1 in [nil, ""]))
           ) do
      {:ok, snapshot}
    end
  end

  @spec redaction_secrets() :: [String.t()]
  def redaction_secrets do
    runtime_env =
      Application.get_env(:eigenforge_core, :runtime_env, %{})
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
      |> Map.merge(System.get_env())

    [runtime_env["EIGENFORGE_HMAC_SECRET"], runtime_env["HOME_ASSISTANT_TOKEN"]]
    |> Enum.reject(&(&1 in [nil, ""]))
  end
end
