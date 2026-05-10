defmodule Eigenforge.Core.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one, name: Eigenforge.Core.Supervisor)
  end

  defp children do
    case Eigenforge.Core.RuntimeConfig.load() do
      {:ok, config} ->
        [
          {Registry, keys: :duplicate, name: Eigenforge.Core.PubSub.Registry},
          {Registry, keys: :duplicate, name: Eigenforge.Core.IoFaultStatus.Registry},
          {Eigenforge.Core.LedgerWriter, config},
          {Eigenforge.Core.IoFaultStatus, config},
          {Eigenforge.Core.SnapshotSubscriber,
           room_id: active_room_id(config),
           db_path: config.core_db_path,
           secret: config.hmac_secret}
        ]

      {:error, _errors} -> []
    end
  end

  defp active_room_id(config) do
    case Eigenforge.Core.SignedConfig.load_device_inventory(config) do
      {:ok, %{active_room: %{"room_id" => room_id}}} -> room_id
      _ -> "placeholder"
    end
  end
end
