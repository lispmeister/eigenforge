defmodule Eigenforge.Core.PendingCommandRecovery do
  @moduledoc """
  Recovery wrapper for pending after-action commands during subscriber startup.
  """

  alias Eigenforge.Core.SnapshotSubscriber

  @spec recover_pending_commands(map()) :: map()
  def recover_pending_commands(state), do: SnapshotSubscriber.recover_pending_commands(state)
end
