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
         {:ok, snapshot} <- ReadModel.snapshot(config.core_db_path, room_id) do
      {:ok, snapshot}
    end
  end
end
