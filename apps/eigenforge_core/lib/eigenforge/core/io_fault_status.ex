defmodule Eigenforge.Core.IoFaultStatus do
  @moduledoc """
  Local PubSub, debug logging, and optional ledger persistence for IO faults.
  """

  use GenServer

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.IoFaultStatusEvent
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.SignedConfig

  @default_server __MODULE__
  @default_registry Module.concat(__MODULE__, Registry)
  @topic "events"

  @connection_fault_types MapSet.new([
    "connection_up",
    "connection_down",
    "reconnecting",
    "degraded",
    "recovered"
  ])

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
      writer: LedgerWriter,
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
        writer: Keyword.get(opts, :writer, LedgerWriter),
        registry_name: registry_name,
        seen_connection_transitions: MapSet.new()
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:record, attrs}, _from, state) do
    with {:ok, event} <- build_event(attrs, state),
         :ok <- append_debug_log(event, state),
         {:ok, state} <- maybe_persist(event, attrs, state) do
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
    payload =
      event
      |> Contracts.signable_map()
      |> redact(state.redactions)
      |> Contracts.canonical_json()

    state.log_path
    |> Path.dirname()
    |> File.mkdir_p()
    |> case do
      :ok -> File.write(state.log_path, payload <> "\n", [:append])
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_persist(event, attrs, state) do
    if persist_to_ledger?(event.fault_type, attrs) do
      if duplicate_connection_transition?(event, state) do
        {:ok, state}
      else
        LedgerWriter.append(state.writer, %{
          event_type: ledger_event_type(event.fault_type),
          subject: "io_adapter",
          source_app: "eigenforge_core",
          payload: Contracts.signable_map(event)
        })
        |> case do
          {:ok, _ledger_event} -> {:ok, remember_connection_transition(event, state)}
          {:error, reason} -> {:error, reason}
        end
      end
    else
      {:ok, state}
    end
  end

  defp persist_to_ledger?(fault_type, attrs) do
    MapSet.member?(@connection_fault_types, fault_type) or
      Map.get(attrs, :ooda_relevant, false) or
      Map.get(attrs, :audit, false)
  end

  defp ledger_event_type(fault_type) do
    if MapSet.member?(@connection_fault_types, fault_type),
      do: "connection_status_observed",
      else: "io_fault_observed"
  end

  defp duplicate_connection_transition?(event, state) do
    case connection_transition_key(event) do
      nil -> false
      key -> MapSet.member?(state.seen_connection_transitions, key)
    end
  end

  defp remember_connection_transition(event, state) do
    case connection_transition_key(event) do
      nil -> state
      key -> %{state | seen_connection_transitions: MapSet.put(state.seen_connection_transitions, key)}
    end
  end

  defp connection_transition_key(event) do
    if MapSet.member?(@connection_fault_types, event.fault_type) do
      correlation_id = get_in(event.metadata || %{}, ["correlation_id"])
      if blank?(correlation_id), do: nil, else: {event.fault_type, correlation_id}
    end
  end

  defp publish(event, registry_name) do
    Registry.dispatch(registry_name, @topic, fn entries ->
      Enum.each(entries, fn {pid, _value} -> send(pid, {:io_fault_status, event}) end)
    end)
  end

  defp redact(map, redactions) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, redact(value, redactions)} end)
  end

  defp redact(list, redactions) when is_list(list), do: Enum.map(list, &redact(&1, redactions))

  defp redact(value, redactions) when is_binary(value) do
    Enum.reduce(redactions, value, fn secret, acc -> String.replace(acc, secret, "[REDACTED]") end)
  end

  defp redact(value, _redactions), do: value

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
