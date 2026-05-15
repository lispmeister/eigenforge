defmodule Eigenforge.Core.IoFaultStatus do
  @moduledoc """
  Compatibility wrapper for the IO-owned fault/status process.
  """

  alias Eigenforge.IO.FaultStatus
  alias Eigenforge.Core.RuntimeConfig

  @default_server __MODULE__

  @spec start_link(RuntimeConfig.t() | keyword()) :: GenServer.on_start()
  def start_link(%RuntimeConfig{} = config) do
    FaultStatus.start_link(
      log_path: config.io_fault_status_log,
      hmac_secret: config.hmac_secret,
      home_assistant_token: config.home_assistant && config.home_assistant[:token],
      default_room_id: default_room_id(config),
      registry_name: Eigenforge.IO.FaultStatus.Registry,
      name: @default_server
    )
  end

  def start_link(opts) when is_list(opts) do
    FaultStatus.start_link(Keyword.put_new(opts, :name, @default_server))
  end

  @spec child_spec(RuntimeConfig.t() | keyword()) :: Supervisor.child_spec()
  def child_spec(%RuntimeConfig{} = config) do
    %{id: @default_server, start: {__MODULE__, :start_link, [config]}}
  end

  def child_spec(opts) when is_list(opts) do
    %{id: Keyword.get(opts, :name, @default_server), start: {__MODULE__, :start_link, [opts]}}
  end

  @spec record(GenServer.server(), map()) :: {:ok, term()} | {:error, term()}
  defdelegate record(server \\ @default_server, attrs), to: FaultStatus

  @spec subscribe(atom() | pid()) :: {:ok, term()} | {:error, term()}
  defdelegate subscribe(registry_name \\ Eigenforge.IO.FaultStatus.Registry), to: FaultStatus

  defp default_room_id(config) do
    case Eigenforge.Core.SignedConfig.load_device_inventory(config) do
      {:ok, %{active_room: %{"room_id" => room_id}}} -> room_id
      _ -> nil
    end
  end
end
