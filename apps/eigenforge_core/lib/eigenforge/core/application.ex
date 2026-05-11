defmodule Eigenforge.Core.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    with {:ok, config} <- Eigenforge.Core.RuntimeConfig.load(),
         {:ok, %{active_room_id: room_id}} <- Eigenforge.Core.Bootstrap.validate(config) do
      Supervisor.start_link(children(config, room_id), strategy: :one_for_one, name: Eigenforge.Core.Supervisor)
    end
  end

  defp children(config, room_id) do
    [
      {Registry, keys: :duplicate, name: Eigenforge.Core.PubSub.Registry},
      {Registry, keys: :duplicate, name: Eigenforge.Core.IoFaultStatus.Registry},
      {Eigenforge.Core.LedgerWriter, config},
      {Eigenforge.Core.IoFaultStatus, config},
      {Eigenforge.Core.SnapshotSubscriber,
       room_id: room_id,
       db_path: config.core_db_path,
       io_mode: Atom.to_string(config.io_mode),
       after_action_timeout_ms: config.after_action_timeout_ms,
       secret: config.hmac_secret}
    ]
  end
end
