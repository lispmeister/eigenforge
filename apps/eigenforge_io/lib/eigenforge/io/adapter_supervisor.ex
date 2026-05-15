defmodule Eigenforge.IO.AdapterSupervisor do
  @moduledoc """
  Supervises the mode-appropriate IO adapter subtree.
  """

  use Supervisor

  alias Eigenforge.Core.RuntimeConfig

  @default_server __MODULE__

  @spec start_link(RuntimeConfig.t() | keyword()) :: Supervisor.on_start()
  def start_link(%RuntimeConfig{} = config) do
    start_link([config: config, name: @default_server])
  end

  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name, @default_server)

    case name do
      nil -> Supervisor.start_link(__MODULE__, init_opts)
      _ -> Supervisor.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @spec child_spec(RuntimeConfig.t() | keyword()) :: Supervisor.child_spec()
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
    config = Keyword.fetch!(opts, :config)

    Supervisor.init(children(config), strategy: :one_for_one)
  end

  defp children(%RuntimeConfig{io_mode: :simulator} = config) do
    [
      {Eigenforge.IO.SimulatorClient,
      [
         fixtures_dir: config.simulator_snapshots_dir,
         io_fault_status: Eigenforge.IO.FaultStatus,
         pubsub_registry: Eigenforge.Core.PubSub.Registry,
         name: nil
       ]}
    ]
  end

  defp children(%RuntimeConfig{io_mode: :home_assistant} = config) do
    [
      {Eigenforge.IO.HomeAssistantClient,
       [
         room_id: "placeholder",
         home_assistant: config.home_assistant,
         hmac_secret: config.hmac_secret,
         ha_reconnect_max_ms: config.ha_reconnect_max_ms,
         io_fault_status: Eigenforge.IO.FaultStatus,
         pubsub_registry: Eigenforge.Core.PubSub.Registry,
         mailbox_registry: Eigenforge.Mailbox.Registry,
         mailbox_receipt_store: Eigenforge.Mailbox.ReceiptStore,
         command_execution_store: Eigenforge.IO.CommandExecutionStore,
         transport: Eigenforge.IO.HomeAssistantTransport.Live,
         name: nil
       ]}
    ]
  end
end
