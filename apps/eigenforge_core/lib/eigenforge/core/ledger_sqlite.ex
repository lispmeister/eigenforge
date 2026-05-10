defmodule Eigenforge.Core.LedgerSQLite do
  @moduledoc """
  Local SQLite storage helpers for the V1 append-only `ledger_events` table.

  V1 keeps the durable core ledger in a node-local SQLite database. This module
  initializes the database file, enables WAL mode, creates the append-only
  table, and exposes a small append/query surface that later writer processes
  can build on.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.LedgerEvent
  alias Eigenforge.Core.RuntimeConfig

  @decision_chain_event_types ~w(
    reasoner_outcome_recorded
    capability_check_recorded
    policy_decision_recorded
    command_envelope_issued
    after_action_recorded
    stale_snapshot_denied
  )

  @genesis_previous_hash "eigenforge-ledger-genesis-v1"

  @type init_error ::
          {:sqlite_unavailable, term()}
          | {:sqlite_init_failed, binary()}
          | {:sqlite_query_failed, binary()}

  @spec init(RuntimeConfig.t() | String.t(), String.t() | nil) :: :ok | {:error, init_error()}
  def init(%RuntimeConfig{core_db_path: db_path, core_node_id: core_node_id}), do: init(db_path, core_node_id)

  def init(db_path, _core_node_id \\ nil) when is_binary(db_path) do
    with :ok <- ensure_parent_dir(db_path),
         {:ok, _} <- sqlite(db_path, init_sql()) do
      :ok
    end
  end

  @spec append_event(String.t(), LedgerEvent.t() | map()) :: :ok | {:error, init_error()}
  def append_event(db_path, %LedgerEvent{} = event) when is_binary(db_path) do
    payload_json = Contracts.canonical_json(event.payload)
    quorum_ref_json = Contracts.canonical_json(event.quorum_ref)

    sql = """
    INSERT INTO ledger_events (
      sequence,
      event_id,
      event_type,
      core_node_id,
      consensus_decision_id,
      consensus_status,
      quorum_ref,
      causation_id,
      correlation_id,
      subject,
      source_app,
      occurred_at,
      observed_at,
      persisted_at,
      format_version,
      schema_id,
      schema_version,
      payload,
      payload_hash,
      previous_event_hash,
      event_hash,
      signature_version,
      signature
    ) VALUES (
      #{event.sequence},
      #{sql_string(event.event_id)},
      #{sql_string(event.event_type)},
      #{sql_string(event.core_node_id)},
      #{sql_nullable(event.consensus_decision_id)},
      #{sql_nullable(event.consensus_status)},
      #{sql_string(quorum_ref_json)},
      #{sql_nullable(event.causation_id)},
      #{sql_nullable(event.correlation_id)},
      #{sql_string(event.subject)},
      #{sql_string(event.source_app)},
      #{sql_string(event.occurred_at)},
      #{sql_string(event.observed_at)},
      #{sql_string(event.persisted_at)},
      #{sql_string(event.format_version)},
      #{sql_string(event.schema_id)},
      #{event.schema_version},
      #{sql_string(payload_json)},
      #{sql_string(event.payload_hash)},
      #{sql_string(event.previous_event_hash)},
      #{sql_string(event.event_hash)},
      #{sql_string(event.signature_version)},
      #{sql_string(event.signature)}
    );
    """

    case sqlite(db_path, sql) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def append_event(db_path, event_map) when is_binary(db_path) and is_map(event_map) do
    db_path
    |> append_event(LedgerEvent.new!(event_map))
  end

  @spec query(String.t(), String.t()) :: {:ok, binary()} | {:error, init_error()}
  def query(db_path, sql) when is_binary(db_path) and is_binary(sql), do: sqlite(db_path, sql)

  @spec query_json(String.t(), String.t()) :: {:ok, term()} | {:error, init_error() | term()}
  def query_json(db_path, sql) when is_binary(db_path) and is_binary(sql) do
    case System.cmd("sqlite3", ["-json", db_path, sql], stderr_to_stdout: true) do
      {output, 0} ->
        if String.trim(output) == "" do
          {:ok, []}
        else
          Contracts.decode_json(output)
        end

      {output, _code} -> {:error, {:sqlite_query_failed, output}}
    end
  rescue
    error -> {:error, {:sqlite_init_failed, Exception.message(error)}}
  end

  @spec tail(String.t()) :: {:ok, map()} | {:error, init_error() | term()}
  def tail(db_path) when is_binary(db_path) do
    case query_json(
           db_path,
           "SELECT sequence, event_id, event_hash FROM ledger_events ORDER BY sequence DESC LIMIT 1;"
         ) do
      {:ok, [row]} -> {:ok, row}
      {:ok, []} -> {:error, :empty_ledger}
      {:error, reason} -> {:error, reason}
    end
  end

  defp init_sql do
    decision_event_list =
      @decision_chain_event_types
      |> Enum.map_join(", ", &"'#{&1}'")

    """
    PRAGMA journal_mode=WAL;
    PRAGMA foreign_keys=ON;

    CREATE TABLE IF NOT EXISTS ledger_events (
      sequence INTEGER PRIMARY KEY,
      event_id TEXT NOT NULL UNIQUE,
      event_type TEXT NOT NULL,
      core_node_id TEXT NOT NULL,
      consensus_decision_id TEXT,
      consensus_status TEXT,
      quorum_ref TEXT NOT NULL,
      causation_id TEXT,
      correlation_id TEXT,
      subject TEXT NOT NULL,
      source_app TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      observed_at TEXT NOT NULL,
      persisted_at TEXT NOT NULL,
      format_version TEXT NOT NULL,
      schema_id TEXT NOT NULL,
      schema_version INTEGER NOT NULL,
      payload TEXT NOT NULL,
      payload_hash TEXT NOT NULL,
      previous_event_hash TEXT NOT NULL,
      event_hash TEXT NOT NULL UNIQUE,
      signature_version TEXT NOT NULL,
      signature TEXT NOT NULL,
      CHECK (sequence >= 1),
      CHECK (quorum_ref = '{}'),
      CHECK (
        sequence <> 1 OR (
          event_type = 'ledger_genesis' AND
          previous_event_hash = '#{@genesis_previous_hash}'
        )
      ),
      CHECK (sequence = 1 OR event_type <> 'ledger_genesis'),
      CHECK (
        event_type NOT IN (#{decision_event_list}) OR (
          consensus_decision_id IS NOT NULL AND
          consensus_decision_id <> '' AND
          consensus_status IS NOT NULL AND
          consensus_status <> ''
        )
      )
    );

    CREATE TRIGGER IF NOT EXISTS ledger_events_no_update
    BEFORE UPDATE ON ledger_events
    BEGIN
      SELECT RAISE(ABORT, 'ledger_events is append-only');
    END;

    CREATE TRIGGER IF NOT EXISTS ledger_events_no_delete
    BEFORE DELETE ON ledger_events
    BEGIN
      SELECT RAISE(ABORT, 'ledger_events is append-only');
    END;
    """
  end

  defp sqlite(db_path, sql) do
    case System.cmd("sqlite3", [db_path, sql], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} when code in [127] -> {:error, {:sqlite_unavailable, output}}
      {output, _code} -> {:error, {:sqlite_query_failed, output}}
    end
  rescue
    error -> {:error, {:sqlite_init_failed, Exception.message(error)}}
  end

  defp ensure_parent_dir(db_path) do
    db_path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp sql_string(value) when is_binary(value), do: "'#{String.replace(value, "'", "''")}'"
  defp sql_nullable(nil), do: "NULL"
  defp sql_nullable(value) when is_binary(value), do: sql_string(value)
end
