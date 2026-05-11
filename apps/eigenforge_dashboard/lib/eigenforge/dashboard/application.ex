defmodule Eigenforge.Dashboard.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Eigenforge.Dashboard.PubSub},
      Eigenforge.Dashboard.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Eigenforge.Dashboard.Supervisor)
  end
end
