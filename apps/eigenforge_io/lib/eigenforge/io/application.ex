defmodule Eigenforge.IO.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one, name: Eigenforge.IO.Supervisor)
  end

  defp children do
    case Eigenforge.Core.RuntimeConfig.load() do
      {:ok, %Eigenforge.Core.RuntimeConfig{io_mode: :simulator} = config} ->
        [{Eigenforge.IO.SimulatorClient, config}]

      {:ok, _config} ->
        []

      {:error, _errors} ->
        []
    end
  end
end
