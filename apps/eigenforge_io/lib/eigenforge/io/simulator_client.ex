defmodule Eigenforge.IO.SimulatorClient do
  @moduledoc """
  Publishes unsigned simulator fixtures onto the core snapshot topic.
  """

  use GenServer

  alias Eigenforge.Core.PubSub
  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.SimulatorFixture
  alias Eigenforge.IO.FaultStatus

  @default_server __MODULE__

  @spec start_link(keyword() | RuntimeConfig.t()) :: GenServer.on_start()
  def start_link(%RuntimeConfig{} = config) do
    start_link(
      fixtures_dir: config.simulator_snapshots_dir,
      io_fault_status: FaultStatus,
      pubsub_registry: Eigenforge.Core.PubSub.Registry,
      name: @default_server
    )
  end

  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name, @default_server)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      _ -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @spec child_spec(keyword() | RuntimeConfig.t()) :: Supervisor.child_spec()
  def child_spec(%RuntimeConfig{} = config) do
    %{
      id: @default_server,
      start: {__MODULE__, :start_link, [config]}
    }
  end

  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :name, @default_server),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def init(opts) do
    state = %{
      fixtures_dir: Keyword.fetch!(opts, :fixtures_dir),
      io_fault_status: Keyword.get(opts, :io_fault_status, FaultStatus),
      pubsub_registry: Keyword.get(opts, :pubsub_registry, Eigenforge.Core.PubSub.Registry)
    }

    send(self(), :publish_all)
    {:ok, state}
  end

  @impl true
  def handle_info(:publish_all, state) do
    _ = publish_all(state)
    {:noreply, state}
  end

  defp publish_all(state) do
    state.fixtures_dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, ".sig"))
    |> Enum.sort()
    |> Enum.each(fn path ->
      with {:ok, %{scenario_id: scenario_id, snapshot: snapshot, intent: intent}} <- SimulatorFixture.load_file(path) do
        room_id = snapshot["room_id"]
        PubSub.publish("io_state:room:#{room_id}", snapshot, registry_name: state.pubsub_registry)
        maybe_publish_fault(state.io_fault_status, room_id, scenario_id, snapshot, intent)
      end
    end)
  end

  defp maybe_publish_fault(io_fault_status, room_id, scenario_id, snapshot, intent) do
    co2_status =
      snapshot
      |> Map.get("source_status", %{})
      |> Map.get("co2")

    if co2_status in ~w(malformed missing unknown unavailable) do
      _ =
        FaultStatus.record(io_fault_status, %{
          source: "simulator",
          room_id: room_id,
          fault_type: "malformed_observation",
          ooda_relevant: true,
          metadata: %{
            "scenario_id" => scenario_id,
            "co2_status" => co2_status,
            "fixture_intent" => intent || %{}
          }
        })

      :ok
    else
      :ok
    end
  end
end
