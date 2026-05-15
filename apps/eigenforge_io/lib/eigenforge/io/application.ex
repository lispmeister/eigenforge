defmodule Eigenforge.IO.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    with {:ok, config} <- Eigenforge.Core.RuntimeConfig.load(),
         :ok <- validate_startup_inputs(config) do
      Supervisor.start_link(children(config), strategy: :one_for_one, name: Eigenforge.IO.Supervisor)
    end
  end

  defp children(%Eigenforge.Core.RuntimeConfig{io_mode: :simulator} = config),
    do: [
      {Registry, keys: :duplicate, name: Eigenforge.IO.FaultStatus.Registry},
      {Eigenforge.IO.FaultStatus, config},
      {Eigenforge.IO.CommandExecutionStore,
       path: config.io_command_store_path, name: Eigenforge.IO.CommandExecutionStore},
      {Eigenforge.IO.AdapterSupervisor, config}
    ]

  defp children(%Eigenforge.Core.RuntimeConfig{io_mode: :home_assistant} = config),
    do: [
      {Registry, keys: :duplicate, name: Eigenforge.IO.FaultStatus.Registry},
      {Eigenforge.IO.FaultStatus, config},
      {Eigenforge.IO.CommandExecutionStore,
       path: config.io_command_store_path, name: Eigenforge.IO.CommandExecutionStore},
      {Eigenforge.IO.AdapterSupervisor, config}
    ]

  defp validate_startup_inputs(%Eigenforge.Core.RuntimeConfig{io_mode: :simulator} = config) do
    Eigenforge.Core.SimulatorFixture.validate_directory(config.simulator_snapshots_dir)
  end

  defp validate_startup_inputs(%Eigenforge.Core.RuntimeConfig{}), do: :ok
end
