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
      {Eigenforge.Core.LedgerWriter, config},
      {Eigenforge.Core.FaultStatusSubscriber,
       room_id: room_id,
       db_path: config.core_db_path,
       writer: Eigenforge.Core.LedgerWriter,
       mailbox_receipt_store: Eigenforge.Mailbox.ReceiptStore,
       after_action_observer: Eigenforge.Core.AfterActionObserver,
       io_fault_status_registry: Eigenforge.IO.FaultStatus.Registry,
       snapshot_subscriber: Eigenforge.Core.SnapshotSubscriber,
       name: Eigenforge.Core.FaultStatusSubscriber},
      {Eigenforge.Core.QuorumFinalizedSubscriber,
       room_id: room_id,
       db_path: config.core_db_path,
       secret: config.hmac_secret,
       mailbox_registry: Eigenforge.Mailbox.Registry,
       name: Eigenforge.Core.QuorumFinalizedSubscriber},
      {Eigenforge.Core.SnapshotSubscriber,
       room_id: room_id,
       db_path: config.core_db_path,
       io_mode: Atom.to_string(config.io_mode),
       after_action_timeout_ms: config.after_action_timeout_ms,
       secret: config.hmac_secret}
    ]
  end
end
