defmodule Eigenforge.Dashboard.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([], strategy: :one_for_one, name: Eigenforge.Dashboard.Supervisor)
  end
end
