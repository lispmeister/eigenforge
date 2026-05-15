defmodule Eigenforge.Core.LedgerSQLite do
  @moduledoc """
  Local SQLite storage helpers for the V1 append-only `ledger_events` table.

  Uses exqlite for supervised connections, parameterized queries, and WAL mode.
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
          | {:sqlite_init_failed, term()}
          | {:sqlite_query_failed, term()}

  @spec init(RuntimeConfig.t() | String.t(), String.t() | nil) :: :ok | {:error, init_error()}
  def init(%RuntimeConfig{core_db_path: db_path, core_node_id: core_node_id}),
    do: init(db_path, core_node_id)

  def init(db_path, _core_node_id \\ nil) when is_binary(db_path) do
    with :ok <- ensure_parent_dir(db_path),
         {:ok, conn} <- open(db_path) do
      result =
        Enum.reduce_while(init_statements(), :ok, fn sql, :ok ->
          case Exqlite.Sqlite3.execute(conn, sql) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, {:sqlite_init_failed, reason}}}
          end
        end)

      Exqlite.Sqlite3.close(conn)
      result
    end
  end

  @spec open(String.t()) :: {:ok, Exqlite.Sqlite3.db()} | {:error, init_error()}
  def open(db_path) when is_binary(db_path) do
    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, {:sqlite_unavailable, reason}}
    end
  end

  @spec close(Exqlite.Sqlite3.db()) :: :ok
  def close(conn), do: Exqlite.Sqlite3.close(conn)

  @spec begin_immediate(Exqlite.Sqlite3.db()) :: :ok | {:error, init_error()}
  def begin_immediate(conn), do: execute_conn(conn, "BEGIN IMMEDIATE;")

  @spec commit(Exqlite.Sqlite3.db()) :: :ok | {:error, init_error()}
  def commit(conn), do: execute_conn(conn, "COMMIT;")

  @spec rollback(Exqlite.Sqlite3.db()) :: :ok | {:error, init_error()}
  def rollback(conn), do: execute_conn(conn, "ROLLBACK;")

  @spec append_event(String.t() | Exqlite.Sqlite3.db(), LedgerEvent.t() | map()) ::
          :ok | {:error, init_error()}
  def append_event(db_path, %LedgerEvent{} = event) when is_binary(db_path) do
    payload_json = Contracts.canonical_json(event.payload)
    quorum_ref_json = Contracts.canonical_json(event.quorum_ref)

    sql = """
    INSERT INTO ledger_events (
      sequence, event_id, event_type, core_node_id,
      consensus_decision_id, consensus_status, quorum_ref,
      causation_id, correlation_id, subject, source_app,
      occurred_at, observed_at, persisted_at,
      format_version, schema_id, schema_version,
      payload, payload_hash, previous_event_hash, event_hash,
      signature_version, signature
    ) VALUES (
      ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11,
      ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23
    )
    """

    params = [
      event.sequence,
      event.event_id,
      event.event_type,
      event.core_node_id,
      event.consensus_decision_id,
      event.consensus_status,
      quorum_ref_json,
      event.causation_id,
      event.correlation_id,
      event.subject,
      event.source_app,
      event.occurred_at,
      event.observed_at,
      event.persisted_at,
      event.format_version,
      event.schema_id,
      event.schema_version,
      payload_json,
      event.payload_hash,
      event.previous_event_hash,
      event.event_hash,
      event.signature_version,
      event.signature
    ]

    with {:ok, conn} <- open(db_path),
         {:ok, stmt} <- prepare(conn, sql),
         :ok <- Exqlite.Sqlite3.bind(stmt, params) do
      result = Exqlite.Sqlite3.step(conn, stmt)
      Exqlite.Sqlite3.release(conn, stmt)
      Exqlite.Sqlite3.close(conn)

      case result do
        :done -> :ok
        {:error, reason} -> {:error, {:sqlite_query_failed, reason}}
      end
    end
  end

  def append_event(conn, %LedgerEvent{} = event) do
    payload_json = Contracts.canonical_json(event.payload)
    quorum_ref_json = Contracts.canonical_json(event.quorum_ref)

    sql = """
    INSERT INTO ledger_events (
      sequence, event_id, event_type, core_node_id,
      consensus_decision_id, consensus_status, quorum_ref,
      causation_id, correlation_id, subject, source_app,
      occurred_at, observed_at, persisted_at,
      format_version, schema_id, schema_version,
      payload, payload_hash, previous_event_hash, event_hash,
      signature_version, signature
    ) VALUES (
      ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11,
      ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23
    )
    """

    params = [
      event.sequence,
      event.event_id,
      event.event_type,
      event.core_node_id,
      event.consensus_decision_id,
      event.consensus_status,
      quorum_ref_json,
      event.causation_id,
      event.correlation_id,
      event.subject,
      event.source_app,
      event.occurred_at,
      event.observed_at,
      event.persisted_at,
      event.format_version,
      event.schema_id,
      event.schema_version,
      payload_json,
      event.payload_hash,
      event.previous_event_hash,
      event.event_hash,
      event.signature_version,
      event.signature
    ]

    with {:ok, stmt} <- prepare(conn, sql),
         :ok <- Exqlite.Sqlite3.bind(stmt, params) do
      result = Exqlite.Sqlite3.step(conn, stmt)
      Exqlite.Sqlite3.release(conn, stmt)

      case result do
        :done -> :ok
        {:error, reason} -> {:error, {:sqlite_query_failed, reason}}
      end
    end
  end

  def append_event(db_path, event_map) when is_binary(db_path) and is_map(event_map) do
    append_event(db_path, LedgerEvent.new!(event_map))
  end

  @spec query(String.t(), String.t()) :: {:ok, binary()} | {:error, init_error()}
  def query(db_path, sql) when is_binary(db_path) and is_binary(sql) do
    with {:ok, conn} <- open(db_path) do
      result = Exqlite.Sqlite3.execute(conn, sql)
      Exqlite.Sqlite3.close(conn)

      case result do
        :ok -> {:ok, ""}
        {:error, reason} -> {:error, {:sqlite_query_failed, reason}}
      end
    end
  end

  def query(conn, sql) when is_binary(sql) do
    case Exqlite.Sqlite3.execute(conn, sql) do
      :ok -> {:ok, ""}
      {:error, reason} -> {:error, {:sqlite_query_failed, reason}}
    end
  end

  @spec query_json(String.t(), String.t()) :: {:ok, term()} | {:error, init_error() | term()}
  def query_json(db_path, sql) when is_binary(db_path) and is_binary(sql) do
    with {:ok, conn} <- open(db_path),
         {:ok, stmt} <- prepare(conn, sql),
         {:ok, columns} <- Exqlite.Sqlite3.columns(conn, stmt),
         {:ok, rows} <- Exqlite.Sqlite3.fetch_all(conn, stmt, 500) do
      Exqlite.Sqlite3.release(conn, stmt)
      Exqlite.Sqlite3.close(conn)
      {:ok, Enum.map(rows, &zip_row(columns, &1))}
    end
  end

  def query_json(conn, sql) when is_binary(sql) do
    with {:ok, stmt} <- prepare(conn, sql),
         {:ok, columns} <- Exqlite.Sqlite3.columns(conn, stmt),
         {:ok, rows} <- Exqlite.Sqlite3.fetch_all(conn, stmt, 500) do
      Exqlite.Sqlite3.release(conn, stmt)
      {:ok, Enum.map(rows, &zip_row(columns, &1))}
    end
  end

  @spec tail(String.t() | Exqlite.Sqlite3.db()) :: {:ok, map()} | {:error, init_error() | term()}
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

  def tail(conn) do
    case query_json(conn, "SELECT sequence, event_id, event_hash FROM ledger_events ORDER BY sequence DESC LIMIT 1;") do
      {:ok, [row]} -> {:ok, row}
      {:ok, []} -> {:error, :empty_ledger}
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare(conn, sql) do
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} -> {:ok, stmt}
      {:error, reason} -> {:error, {:sqlite_query_failed, reason}}
    end
  end

  defp zip_row(columns, values) do
    columns
    |> Enum.zip(values)
    |> Map.new()
  end

  defp execute_conn(conn, sql) do
    case Exqlite.Sqlite3.execute(conn, sql) do
      :ok -> :ok
      {:error, reason} -> {:error, {:sqlite_query_failed, reason}}
    end
  end

  defp ensure_parent_dir(db_path) do
    db_path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp init_statements do
    decision_event_list =
      @decision_chain_event_types
      |> Enum.map_join(", ", &"'#{&1}'")

    [
      "PRAGMA journal_mode=WAL",
      "PRAGMA foreign_keys=ON",
      """
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
      )
      """,
      """
      CREATE TRIGGER IF NOT EXISTS ledger_events_no_update
      BEFORE UPDATE ON ledger_events
      BEGIN
        SELECT RAISE(ABORT, 'ledger_events is append-only');
      END
      """,
      """
      CREATE TRIGGER IF NOT EXISTS ledger_events_no_delete
      BEFORE DELETE ON ledger_events
      BEGIN
        SELECT RAISE(ABORT, 'ledger_events is append-only');
      END
      """
    ]
  end
end
