defmodule Eigenforge.IO.FaultStatus do
  @moduledoc """
  IO-owned fault/status publisher and debug log writer.
  """

  use GenServer

  alias Eigenforge.Contracts.IoFaultStatusEvent
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.SignedConfig
  alias Eigenforge.IO.FaultStatusLog

  @default_server __MODULE__
  @default_registry __MODULE__.Registry
  @topic "events"

  @type record_attrs :: %{
          required(:source) => String.t(),
          required(:fault_type) => String.t(),
          optional(:room_id) => String.t(),
          optional(:message) => String.t() | nil,
          optional(:source_received_seq) => integer(),
          optional(:source_received_monotonic_ms) => integer(),
          optional(:metadata) => map(),
          optional(:ooda_relevant) => boolean(),
          optional(:audit) => boolean()
        }

  @spec start_link(RuntimeConfig.t() | keyword()) :: GenServer.on_start()
  def start_link(%RuntimeConfig{} = config) do
    start_link(
      log_path: config.io_fault_status_log,
      hmac_secret: config.hmac_secret,
      home_assistant_token: config.home_assistant && config.home_assistant[:token],
      default_room_id: default_room_id(config),
      registry_name: @default_registry,
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

  @spec child_spec(RuntimeConfig.t() | keyword()) :: Supervisor.child_spec()
  def child_spec(%RuntimeConfig{} = config) do
    %{id: @default_server, start: {__MODULE__, :start_link, [config]}}
  end

  def child_spec(opts) when is_list(opts) do
    %{id: Keyword.get(opts, :name, @default_server), start: {__MODULE__, :start_link, [opts]}}
  end

  @spec subscribe(atom() | pid()) :: {:ok, term()} | {:error, term()}
  def subscribe(registry_name \\ @default_registry) do
    Registry.register(registry_name, @topic, [])
  end

  @spec record(GenServer.server(), record_attrs()) ::
          {:ok, IoFaultStatusEvent.t()} | {:error, term()}
  def record(server \\ @default_server, attrs) when is_map(attrs) do
    GenServer.call(server, {:record, attrs})
  end

  @impl true
  def init(opts) do
    with {:ok, log_path} <- fetch_option(opts, :log_path),
         {:ok, registry_name} <- fetch_registry(opts) do
      state = %{
        log_path: log_path,
        redactions:
          opts
          |> Keyword.take([:hmac_secret, :home_assistant_token])
          |> Keyword.values()
          |> Enum.reject(&blank?/1),
        default_room_id: Keyword.get(opts, :default_room_id),
        registry_name: registry_name
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:record, attrs}, _from, state) do
    with {:ok, event} <- build_event(attrs, state),
         :ok <- append_debug_log(event, state) do
      publish(event, state.registry_name)
      {:reply, {:ok, event}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp build_event(attrs, state) do
    room_id =
      Map.get(attrs, :room_id) ||
        state.default_room_id ||
        raise ArgumentError, "missing room_id for io fault/status event"

    now = now()

    event =
      IoFaultStatusEvent.new!(%{
        event_id: unique_event_id(Map.fetch!(attrs, :fault_type)),
        room_id: room_id,
        source: Map.fetch!(attrs, :source),
        fault_type: Map.fetch!(attrs, :fault_type),
        message: Map.get(attrs, :message),
        observed_at: now,
        metadata: event_metadata(attrs)
      })

    {:ok, event}
  rescue
    error -> {:error, {:invalid_fault_status_event, Exception.message(error)}}
  end

  defp append_debug_log(event, state) do
    case FaultStatusLog.append(event, log_path: state.log_path, redactions: state.redactions) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp publish(event, registry_name) do
    Registry.dispatch(registry_name, @topic, fn entries ->
      Enum.each(entries, fn {pid, _value} -> send(pid, {:io_fault_status, event}) end)
    end)
  end

  defp fetch_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_option, key}}
    end
  end

  defp fetch_registry(opts) do
    case Keyword.fetch(opts, :registry_name) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_option, :registry_name}}
    end
  end

  defp default_room_id(config) do
    case SignedConfig.load_device_inventory(config) do
      {:ok, %{active_room: %{"room_id" => room_id}}} -> room_id
      _ -> nil
    end
  end

  defp event_metadata(attrs) do
    metadata = Map.get(attrs, :metadata, %{})

    metadata
    |> maybe_put_metadata("correlation_id", Map.get(attrs, :correlation_id))
    |> maybe_put_metadata("source_received_seq", Map.get(attrs, :source_received_seq))
    |> maybe_put_metadata(
      "source_received_monotonic_ms",
      Map.get(attrs, :source_received_monotonic_ms)
    )
    |> maybe_put_metadata("ooda_relevant", Map.get(attrs, :ooda_relevant))
    |> maybe_put_metadata("audit", Map.get(attrs, :audit))
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> CanonicalTime.format()
  end

  defp unique_event_id(fault_type) do
    unique = System.unique_integer([:positive, :monotonic])
    "io-fault-#{fault_type}-#{unique}"
  end

  defp blank?(value), do: value in [nil, ""]
end
