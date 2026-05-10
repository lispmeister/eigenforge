defmodule Eigenforge.Mailbox.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(
      [{Registry, keys: :duplicate, name: Eigenforge.Mailbox.Registry}],
      strategy: :one_for_one,
      name: Eigenforge.Mailbox.Supervisor
    )
  end
end
