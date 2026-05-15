defmodule Eigenforge.Core.LedgerWriter do
  @moduledoc """
  Single-writer process for the node-local V1 SQLite ledger.

  The writer owns append sequencing for one core node. Callers submit payloads
  plus minimal ledger metadata and receive either the committed `LedgerEvent`
  or the documented `{:error, :ledger_persistence_failed}` tuple after three
  failed persistence attempts.
  """

  use GenServer

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.LedgerEvent
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.LedgerProjections
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerTooling
  alias Eigenforge.Core.RuntimeConfig

  @signature_version "hmac-sha256-v1"
  @genesis_previous_hash "eigenforge-ledger-genesis-v1"
  @default_server __MODULE__
  @retry_attempts 3

  @type append_attrs :: %{
          required(:event_type) => String.t(),
          required(:payload) => map() | struct(),
          optional(:event_id) => String.t(),
          optional(:consensus_decision_id) => String.t() | nil,
          optional(:consensus_status) => String.t() | nil,
          optional(:quorum_ref) => map(),
          optional(:causation_id) => String.t() | nil,
          optional(:correlation_id) => String.t() | nil,
          optional(:subject) => String.t(),
          optional(:source_app) => String.t(),
          optional(:occurred_at) => String.t(),
          optional(:observed_at) => String.t()
        }

  @type start_opt ::
          {:db_path, String.t()}
          | {:core_node_id, String.t()}
          | {:secret, binary()}
          | {:append_hook, (map() -> any())}
          | {:name, GenServer.name()}

  @type state :: %{
          db_path: String.t(),
          core_node_id: String.t(),
          secret: binary(),
          conn: Exqlite.Sqlite3.db(),
          append_hook: (map() -> any()) | nil
        }

  @spec start_link(RuntimeConfig.t() | [start_opt()]) :: GenServer.on_start()
  def start_link(%RuntimeConfig{} = config) do
    start_link(
      db_path: config.core_db_path,
      core_node_id: config.core_node_id,
      secret: config.hmac_secret,
      append_hook: nil,
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

  @spec child_spec(RuntimeConfig.t() | [start_opt()]) :: Supervisor.child_spec()
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

  @spec append(GenServer.server(), append_attrs()) ::
          {:ok, LedgerEvent.t()} | {:error, :ledger_persistence_failed}
  def append(server \\ @default_server, attrs) when is_map(attrs) do
    GenServer.call(server, {:append, attrs})
  end

  @impl true
  def init(opts) do
    with {:ok, db_path} <- fetch_option(opts, :db_path),
         {:ok, core_node_id} <- fetch_option(opts, :core_node_id),
         {:ok, secret} <- fetch_option(opts, :secret),
         :ok <- prepare_ledger(db_path, core_node_id, secret),
         :ok <- LedgerProjections.rebuild(db_path),
         {:ok, conn} <- LedgerSQLite.open(db_path) do
      {:ok,
       %{
         db_path: db_path,
         core_node_id: core_node_id,
         secret: secret,
         conn: conn,
         append_hook: Keyword.get(opts, :append_hook)
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, %{conn: conn}) do
    LedgerSQLite.close(conn)
    :ok
  end

  @impl true
  def handle_call({:append, attrs}, _from, state) do
    case append_with_retries(attrs, state, @retry_attempts) do
      {:ok, event} -> {:reply, {:ok, event}, state}
      {:error, _reason} -> {:reply, {:error, :ledger_persistence_failed}, state}
    end
  end

  defp append_with_retries(_attrs, _state, 0), do: {:error, :retries_exhausted}

  defp append_with_retries(attrs, state, attempts_left) do
    case append_once(attrs, state) do
      {:ok, event} -> {:ok, event}
      {:error, _reason} -> append_with_retries(attrs, state, attempts_left - 1)
    end
  end

  defp append_once(attrs, state) do
    conn = state.conn

    with :ok <- LedgerSQLite.begin_immediate(conn),
         {:ok, tail} <- LedgerSQLite.tail(conn),
         {:ok, event} <- build_event(attrs, tail, state),
         :ok <- LedgerSQLite.append_event(conn, event),
         :ok <- maybe_run_append_hook(state.append_hook, event),
         :ok <- LedgerProjections.apply_event(conn, event),
         :ok <- LedgerSQLite.commit(conn) do
      {:ok, event}
    else
      {:error, reason} ->
        _ = LedgerSQLite.rollback(state.conn)
        {:error, reason}
    end
  rescue
    error ->
      _ = LedgerSQLite.rollback(state.conn)
      {:error, {:invalid_append_request, Exception.message(error)}}
  end

  defp maybe_run_append_hook(nil, _event), do: :ok

  defp maybe_run_append_hook(hook, event) when is_function(hook, 1) do
    case hook.(event) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:append_hook_failed, other}}
    end
  end

  defp build_event(attrs, tail, state) do
    tail_sequence = Map.fetch!(tail, "sequence")
    previous_event_hash = Map.fetch!(tail, "event_hash")
    last_event_id = Map.fetch!(tail, "event_id")
    event_type = Map.fetch!(attrs, :event_type)
    payload = attrs |> Map.fetch!(:payload) |> Contracts.signable_map()
    occurred_at = Map.get(attrs, :occurred_at, now())
    observed_at = Map.get(attrs, :observed_at, occurred_at)
    persisted_at = now()

    base = %{
      event_id:
        Map.get_lazy(attrs, :event_id, fn ->
          unique_event_id(event_type, tail_sequence + 1)
        end),
      sequence: tail_sequence + 1,
      event_type: event_type,
      core_node_id: state.core_node_id,
      consensus_decision_id: Map.get(attrs, :consensus_decision_id),
      consensus_status: Map.get(attrs, :consensus_status),
      quorum_ref: Map.get(attrs, :quorum_ref, %{}),
      causation_id: Map.get(attrs, :causation_id, last_event_id),
      correlation_id:
        Map.get_lazy(attrs, :correlation_id, fn ->
          unique_event_id("correlation", tail_sequence + 1)
        end),
      subject: Map.get(attrs, :subject, "eigenforge_core"),
      source_app: Map.get(attrs, :source_app, "eigenforge_core"),
      occurred_at: occurred_at,
      observed_at: observed_at,
      persisted_at: persisted_at,
      format_version: "json-canonical-v1",
      schema_id: "eigenforge.ledger_event",
      schema_version: 1,
      payload: payload,
      payload_hash: Contracts.hash_canonical(payload),
      previous_event_hash: previous_event_hash || @genesis_previous_hash,
      event_hash: "",
      signature_version: @signature_version,
      signature: ""
    }

    event_hash = Contracts.hash_excluding(base, [:event_hash, :signature])
    unsigned = %{base | event_hash: event_hash}

    signature =
      Contracts.sign_hmac_excluding(
        unsigned,
        state.secret,
        [:signature],
        "eigenforge:v1:ledger_event"
      )

    {:ok, LedgerEvent.new!(%{unsigned | signature: signature})}
  end

  defp fetch_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_option, key}}
    end
  end

  defp prepare_ledger(db_path, core_node_id, secret) do
    with :ok <- LedgerSQLite.init(db_path, core_node_id),
         {:ok, [%{"count(*)" => count}]} <-
           LedgerSQLite.query_json(db_path, "SELECT count(*) FROM ledger_events;") do
      if count == 0 do
        LedgerTooling.ensure_genesis(db_path, core_node_id, secret)
      else
        LedgerTooling.verify(db_path, core_node_id, secret)
      end
    end
  end

  defp now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> CanonicalTime.format()
  end

  defp unique_event_id(prefix, sequence) do
    unique = System.unique_integer([:positive, :monotonic])
    "#{prefix}-#{sequence}-#{unique}"
  end
end
