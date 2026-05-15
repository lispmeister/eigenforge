defmodule Eigenforge.Core.LedgerProjections do
  @moduledoc """
  Mutable local SQLite read models derived from committed ledger events and
  live normalized snapshots.

  These tables are convenience projections only. The append-only ledger remains
  authoritative and can rebuild the ledger-derived projection fields at
  startup.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.LedgerEvent
  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Core.LedgerSQLite

  @spec init(String.t()) :: :ok | {:error, term()}
  def init(db_path) when is_binary(db_path) do
    with {:ok, _} <- LedgerSQLite.query(db_path, init_sql()),
         :ok <- ensure_room_state_columns(db_path) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def init(conn) do
    with {:ok, _} <- LedgerSQLite.query(conn, init_sql()),
         :ok <- ensure_room_state_columns(conn) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec rebuild(String.t()) :: :ok | {:error, term()}
  def rebuild(db_path) when is_binary(db_path) do
    with :ok <- init(db_path),
         {:ok, _} <-
           LedgerSQLite.query(
             db_path,
             "DELETE FROM latest_room_control_state; DELETE FROM recent_control_chains;"
           ),
         {:ok, rows} <-
           LedgerSQLite.query_json(db_path, "SELECT * FROM ledger_events ORDER BY sequence ASC;"),
         :ok <- replay_rows(db_path, rows) do
      :ok
    end
  end

  @spec apply_event(String.t(), LedgerEvent.t() | map()) :: :ok | {:error, term()}
  def apply_event(db_path, %LedgerEvent{} = event) when is_binary(db_path) do
    payload = normalize_payload(event.payload)
    correlation_id = fetch_field(event, :correlation_id)
    event_type = fetch_field(event, :event_type)

    # init/1 is performed once at startup or rebuild time; per-event table creation is redundant.
    with {:ok, chain} <- upsert_chain(db_path, event, payload, correlation_id, event_type),
         :ok <- maybe_upsert_room_state(db_path, event, payload, chain, event_type) do
      :ok
    end
  end

  def apply_event(conn, %LedgerEvent{} = event) do
    payload = normalize_payload(event.payload)
    correlation_id = fetch_field(event, :correlation_id)
    event_type = fetch_field(event, :event_type)

    # init/1 is performed once at startup or rebuild time; per-event table creation is redundant.
    with {:ok, chain} <- upsert_chain(conn, event, payload, correlation_id, event_type),
         :ok <- maybe_upsert_room_state(conn, event, payload, chain, event_type) do
      :ok
    end
  end

  def apply_event(db_path, event) when is_binary(db_path) and is_map(event) do
    event
    |> normalize_event()
    |> then(&apply_event(db_path, &1))
  end

  @spec observe_snapshot(String.t(), NormalizedSnapshot.t() | map(), keyword()) ::
          :ok | {:error, term()}
  def observe_snapshot(db_path, snapshot, opts \\ [])

  def observe_snapshot(db_path, %NormalizedSnapshot{} = snapshot, opts) when is_binary(db_path) do
    observe_snapshot(db_path, Contracts.signable_map(snapshot), opts)
  end

  def observe_snapshot(db_path, snapshot, opts) when is_binary(db_path) and is_map(snapshot) do
    snapshot = normalize_payload(snapshot)
    room_id = Map.fetch!(snapshot, "room_id")

    with :ok <- init(db_path) do
      existing = fetch_room_state(db_path, room_id)

      row =
        existing
        |> Map.merge(%{
          "room_id" => room_id,
          "latest_snapshot_id" => snapshot["snapshot_id"],
          "latest_snapshot_hash" => snapshot["snapshot_hash"],
          "co2_ppm" => snapshot["co2_ppm"],
          "humidity_basis_points" => snapshot["humidity_basis_points"],
          "temperature_millicelsius" => snapshot["temperature_millicelsius"],
          "fan_state" => snapshot["fan_state"],
          "io_mode" => Keyword.get(opts, :io_mode, existing["io_mode"]),
          "freshness" => snapshot["freshness"],
          "source_received_seq_fan" =>
            nested_receive_value(snapshot, "source_received_seq", "fan"),
          "source_received_monotonic_ms_fan" =>
            nested_receive_value(snapshot, "source_received_monotonic_ms", "fan"),
          "co2_status" => nested_status(snapshot, "co2"),
          "humidity_status" => nested_status(snapshot, "humidity"),
          "temperature_status" => nested_status(snapshot, "temperature"),
          "fan_status" => nested_status(snapshot, "fan"),
          "updated_at" => Keyword.get(opts, :updated_at, snapshot["normalized_at"])
        })

      upsert_room_state(db_path, row)
    end
  end

  @spec query_json(String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def query_json(db_path, sql) when is_binary(db_path) and is_binary(sql) do
    LedgerSQLite.query_json(db_path, sql)
  end

  defp replay_rows(_db_path, []), do: :ok

  defp replay_rows(db_path, [row | rest]) do
    case apply_event(db_path, row) do
      :ok -> replay_rows(db_path, rest)
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_room_state_columns(target) do
    required_columns = [
      {"source_received_seq_fan", "INTEGER"},
      {"source_received_monotonic_ms_fan", "INTEGER"}
    ]

    with {:ok, rows} <-
           LedgerSQLite.query_json(target, "PRAGMA table_info(latest_room_control_state);") do
      existing = MapSet.new(Enum.map(rows, & &1["name"]))

      Enum.reduce_while(required_columns, :ok, fn {column, type}, :ok ->
        if MapSet.member?(existing, column) do
          {:cont, :ok}
        else
          case LedgerSQLite.query(
                 target,
                 "ALTER TABLE latest_room_control_state ADD COLUMN #{column} #{type};"
               ) do
            {:ok, _} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end
      end)
    end
  end

  defp normalize_event(event) do
    payload =
      event
      |> fetch_field(:payload)
      |> normalize_payload()

    %LedgerEvent{
      causation_id: fetch_field(event, :causation_id),
      consensus_decision_id: fetch_field(event, :consensus_decision_id),
      consensus_status: fetch_field(event, :consensus_status),
      core_node_id: fetch_field(event, :core_node_id),
      correlation_id: fetch_field(event, :correlation_id),
      event_hash: fetch_field(event, :event_hash),
      event_id: fetch_field(event, :event_id),
      event_type: fetch_field(event, :event_type),
      format_version: fetch_field(event, :format_version),
      observed_at: fetch_field(event, :observed_at),
      occurred_at: fetch_field(event, :occurred_at),
      payload: payload,
      payload_hash: fetch_field(event, :payload_hash),
      persisted_at: fetch_field(event, :persisted_at),
      previous_event_hash: fetch_field(event, :previous_event_hash),
      quorum_ref: normalize_payload(fetch_field(event, :quorum_ref)),
      schema_id: fetch_field(event, :schema_id),
      schema_version: fetch_field(event, :schema_version),
      sequence: fetch_field(event, :sequence),
      signature: fetch_field(event, :signature),
      signature_version: fetch_field(event, :signature_version),
      source_app: fetch_field(event, :source_app),
      subject: fetch_field(event, :subject)
    }
  end

  defp upsert_chain(db_path, event, payload, correlation_id, event_type) do
    existing = fetch_chain(db_path, correlation_id)

    row =
      existing
      |> Map.merge(%{
        "correlation_id" => correlation_id,
        "room_id" => room_id_for_event(payload, existing),
        "started_at" => started_at_for_event(event_type, event, existing),
        "latest_event_id" => fetch_field(event, :event_id),
        "latest_event_type" => event_type,
        "snapshot_id" => payload["snapshot_id"] || existing["snapshot_id"],
        "snapshot_hash" => payload["snapshot_hash"] || existing["snapshot_hash"],
        "reasoner_outcome_id" =>
          payload["reasoner_outcome_id"] || existing["reasoner_outcome_id"],
        "reasoner_outcome" => reasoner_outcome_for_event(event_type, payload, existing),
        "policy_decision_id" => payload["policy_decision_id"] || existing["policy_decision_id"],
        "policy_decision" => policy_decision_for_event(event_type, payload, existing),
        "command_id" => command_id_for_event(event_type, payload, existing),
        "effect_key" => effect_key_for_event(event_type, payload, existing),
        "after_action_status" => after_action_status_for_event(event_type, payload, existing),
        "updated_at" => fetch_field(event, :persisted_at)
      })

    with :ok <- upsert_recent_chain(db_path, row) do
      {:ok, row}
    end
  end

  defp maybe_upsert_room_state(db_path, event, payload, chain, event_type) do
    room_id = chain["room_id"] || payload["room_id"]

    if blank?(room_id) do
      :ok
    else
      existing = fetch_room_state(db_path, room_id)

      row =
        existing
        |> Map.merge(%{
          "room_id" => room_id,
          "latest_snapshot_id" => chain["snapshot_id"] || existing["latest_snapshot_id"],
          "latest_snapshot_hash" => chain["snapshot_hash"] || existing["latest_snapshot_hash"],
          "connection_status" => connection_status_for_event(event_type, payload, existing),
          "latest_reasoner_outcome_id" =>
            chain["reasoner_outcome_id"] || existing["latest_reasoner_outcome_id"],
          "latest_policy_decision_id" =>
            chain["policy_decision_id"] || existing["latest_policy_decision_id"],
          "latest_command_id" => latest_command_for_event(event_type, payload, existing),
          "latest_after_action_id" =>
            latest_after_action_for_event(event_type, payload, existing),
          "pending_command_id" => pending_command_for_event(event_type, payload, existing),
          "pending_effect_key" => pending_effect_for_event(event_type, payload, existing),
          "command_lifecycle" => command_lifecycle_for_event(event_type, payload, existing),
          "updated_at" => fetch_field(event, :persisted_at)
        })

      upsert_room_state(db_path, row)
    end
  end

  defp fetch_chain(db_path, correlation_id) do
    case LedgerSQLite.query_json(
           db_path,
           "SELECT * FROM recent_control_chains WHERE correlation_id = #{sql_string(correlation_id)} LIMIT 1;"
         ) do
      {:ok, [row]} -> row
      _ -> %{}
    end
  end

  defp fetch_room_state(db_path, room_id) do
    case LedgerSQLite.query_json(
           db_path,
           "SELECT * FROM latest_room_control_state WHERE room_id = #{sql_string(room_id)} LIMIT 1;"
         ) do
      {:ok, [row]} -> row
      _ -> %{}
    end
  end

  defp upsert_recent_chain(db_path, row) do
    sql = """
    INSERT INTO recent_control_chains (
      correlation_id, room_id, started_at, latest_event_id, latest_event_type,
      snapshot_id, snapshot_hash, reasoner_outcome_id, reasoner_outcome,
      policy_decision_id, policy_decision, command_id, effect_key,
      after_action_status, updated_at
    ) VALUES (
      #{sql_string(row["correlation_id"])},
      #{sql_nullable(row["room_id"])},
      #{sql_nullable(row["started_at"])},
      #{sql_nullable(row["latest_event_id"])},
      #{sql_nullable(row["latest_event_type"])},
      #{sql_nullable(row["snapshot_id"])},
      #{sql_nullable(row["snapshot_hash"])},
      #{sql_nullable(row["reasoner_outcome_id"])},
      #{sql_nullable(row["reasoner_outcome"])},
      #{sql_nullable(row["policy_decision_id"])},
      #{sql_nullable(row["policy_decision"])},
      #{sql_nullable(row["command_id"])},
      #{sql_nullable(row["effect_key"])},
      #{sql_nullable(row["after_action_status"])},
      #{sql_nullable(row["updated_at"])}
    )
    ON CONFLICT(correlation_id) DO UPDATE SET
      room_id = excluded.room_id,
      started_at = excluded.started_at,
      latest_event_id = excluded.latest_event_id,
      latest_event_type = excluded.latest_event_type,
      snapshot_id = excluded.snapshot_id,
      snapshot_hash = excluded.snapshot_hash,
      reasoner_outcome_id = excluded.reasoner_outcome_id,
      reasoner_outcome = excluded.reasoner_outcome,
      policy_decision_id = excluded.policy_decision_id,
      policy_decision = excluded.policy_decision,
      command_id = excluded.command_id,
      effect_key = excluded.effect_key,
      after_action_status = excluded.after_action_status,
      updated_at = excluded.updated_at;
    """

    case LedgerSQLite.query(db_path, sql) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_room_state(db_path, row) do
    sql = """
    INSERT INTO latest_room_control_state (
      room_id, latest_snapshot_id, latest_snapshot_hash, co2_ppm,
      humidity_basis_points, temperature_millicelsius, fan_state, io_mode,
      connection_status, latest_reasoner_outcome_id, latest_policy_decision_id,
      latest_command_id, latest_after_action_id, pending_command_id,
      pending_effect_key, freshness, source_received_seq_fan, source_received_monotonic_ms_fan,
      co2_status, humidity_status,
      temperature_status, fan_status, command_lifecycle, updated_at
    ) VALUES (
      #{sql_string(row["room_id"])},
      #{sql_nullable(row["latest_snapshot_id"])},
      #{sql_nullable(row["latest_snapshot_hash"])},
      #{sql_nullable_int(row["co2_ppm"])},
      #{sql_nullable_int(row["humidity_basis_points"])},
      #{sql_nullable_int(row["temperature_millicelsius"])},
      #{sql_nullable(row["fan_state"])},
      #{sql_nullable(row["io_mode"])},
      #{sql_nullable(row["connection_status"])},
      #{sql_nullable(row["latest_reasoner_outcome_id"])},
      #{sql_nullable(row["latest_policy_decision_id"])},
      #{sql_nullable(row["latest_command_id"])},
      #{sql_nullable(row["latest_after_action_id"])},
      #{sql_nullable(row["pending_command_id"])},
      #{sql_nullable(row["pending_effect_key"])},
      #{sql_nullable(row["freshness"])},
      #{sql_nullable_int(row["source_received_seq_fan"])},
      #{sql_nullable_int(row["source_received_monotonic_ms_fan"])},
      #{sql_nullable(row["co2_status"])},
      #{sql_nullable(row["humidity_status"])},
      #{sql_nullable(row["temperature_status"])},
      #{sql_nullable(row["fan_status"])},
      #{sql_nullable(row["command_lifecycle"])},
      #{sql_nullable(row["updated_at"])}
    )
    ON CONFLICT(room_id) DO UPDATE SET
      latest_snapshot_id = excluded.latest_snapshot_id,
      latest_snapshot_hash = excluded.latest_snapshot_hash,
      co2_ppm = excluded.co2_ppm,
      humidity_basis_points = excluded.humidity_basis_points,
      temperature_millicelsius = excluded.temperature_millicelsius,
      fan_state = excluded.fan_state,
      io_mode = excluded.io_mode,
      connection_status = excluded.connection_status,
      latest_reasoner_outcome_id = excluded.latest_reasoner_outcome_id,
      latest_policy_decision_id = excluded.latest_policy_decision_id,
      latest_command_id = excluded.latest_command_id,
      latest_after_action_id = excluded.latest_after_action_id,
      pending_command_id = excluded.pending_command_id,
      pending_effect_key = excluded.pending_effect_key,
      freshness = excluded.freshness,
      source_received_seq_fan = excluded.source_received_seq_fan,
      source_received_monotonic_ms_fan = excluded.source_received_monotonic_ms_fan,
      co2_status = excluded.co2_status,
      humidity_status = excluded.humidity_status,
      temperature_status = excluded.temperature_status,
      fan_status = excluded.fan_status,
      command_lifecycle = excluded.command_lifecycle,
      updated_at = excluded.updated_at;
    """

    case LedgerSQLite.query(db_path, sql) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp init_sql do
    """
    CREATE TABLE IF NOT EXISTS latest_room_control_state (
      room_id TEXT PRIMARY KEY,
      latest_snapshot_id TEXT,
      latest_snapshot_hash TEXT,
      co2_ppm INTEGER,
      humidity_basis_points INTEGER,
      temperature_millicelsius INTEGER,
      fan_state TEXT,
      io_mode TEXT,
      connection_status TEXT,
      latest_reasoner_outcome_id TEXT,
      latest_policy_decision_id TEXT,
      latest_command_id TEXT,
      latest_after_action_id TEXT,
      pending_command_id TEXT,
      pending_effect_key TEXT,
      freshness TEXT,
      source_received_seq_fan INTEGER,
      source_received_monotonic_ms_fan INTEGER,
      co2_status TEXT,
      humidity_status TEXT,
      temperature_status TEXT,
      fan_status TEXT,
      command_lifecycle TEXT,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS recent_control_chains (
      correlation_id TEXT PRIMARY KEY,
      room_id TEXT,
      started_at TEXT,
      latest_event_id TEXT,
      latest_event_type TEXT,
      snapshot_id TEXT,
      snapshot_hash TEXT,
      reasoner_outcome_id TEXT,
      reasoner_outcome TEXT,
      policy_decision_id TEXT,
      policy_decision TEXT,
      command_id TEXT,
      effect_key TEXT,
      after_action_status TEXT,
      updated_at TEXT NOT NULL
    );
    """
  end

  defp room_id_for_event(payload, existing) do
    payload["room_id"] || parse_room_scope(payload["scope"]) || existing["room_id"]
  end

  defp parse_room_scope(nil), do: nil
  defp parse_room_scope("room:" <> room_id), do: room_id
  defp parse_room_scope(_value), do: nil

  defp reasoner_outcome_for_event("reasoner_outcome_recorded", payload, _existing),
    do: payload["outcome_type"]

  defp reasoner_outcome_for_event(_event_type, _payload, existing),
    do: existing["reasoner_outcome"]

  defp policy_decision_for_event("policy_decision_recorded", payload, _existing),
    do: payload["decision"]

  defp policy_decision_for_event("stale_snapshot_denied", payload, _existing),
    do: payload["decision"]

  defp policy_decision_for_event(_event_type, _payload, existing), do: existing["policy_decision"]

  defp command_id_for_event("command_envelope_issued", payload, _existing),
    do: payload["command_id"]

  defp command_id_for_event("after_action_recorded", payload, existing),
    do: payload["command_id"] || existing["command_id"]

  defp command_id_for_event(_event_type, _payload, existing), do: existing["command_id"]

  defp effect_key_for_event("command_envelope_issued", payload, _existing),
    do: payload["effect_key"]

  defp effect_key_for_event("after_action_recorded", payload, existing),
    do: payload["effect_key"] || existing["effect_key"]

  defp effect_key_for_event(_event_type, _payload, existing), do: existing["effect_key"]

  defp after_action_status_for_event("after_action_recorded", payload, _existing),
    do: payload["status"]

  defp after_action_status_for_event(_event_type, _payload, existing),
    do: existing["after_action_status"]

  defp connection_status_for_event("connection_status_observed", payload, _existing),
    do: payload["fault_type"]

  defp connection_status_for_event(_event_type, _payload, existing),
    do: existing["connection_status"]

  defp latest_command_for_event("command_envelope_issued", payload, _existing),
    do: payload["command_id"]

  defp latest_command_for_event(_event_type, _payload, existing),
    do: existing["latest_command_id"]

  defp latest_after_action_for_event("after_action_recorded", payload, _existing),
    do: payload["after_action_id"]

  defp latest_after_action_for_event(_event_type, _payload, existing),
    do: existing["latest_after_action_id"]

  defp pending_command_for_event("command_envelope_issued", payload, _existing),
    do: payload["command_id"]

  defp pending_command_for_event("after_action_recorded", _payload, _existing), do: nil

  defp pending_command_for_event(_event_type, _payload, existing),
    do: existing["pending_command_id"]

  defp pending_effect_for_event("command_envelope_issued", payload, _existing),
    do: payload["effect_key"]

  defp pending_effect_for_event("after_action_recorded", _payload, _existing), do: nil

  defp pending_effect_for_event(_event_type, _payload, existing),
    do: existing["pending_effect_key"]

  defp command_lifecycle_for_event("command_envelope_issued", _payload, _existing),
    do: "pending_command"

  defp command_lifecycle_for_event("after_action_recorded", payload, _existing),
    do: payload["status"]

  defp command_lifecycle_for_event(_event_type, _payload, existing),
    do: existing["command_lifecycle"]

  defp nested_status(snapshot, source) do
    snapshot
    |> Map.get("source_status", %{})
    |> Map.get(source)
  end

  defp nested_receive_value(snapshot, parent_key, child_key) do
    snapshot
    |> Map.get(parent_key, %{})
    |> Map.get(child_key)
  end

  defp normalize_payload(nil), do: %{}
  defp normalize_payload(binary) when is_binary(binary), do: Contracts.decode_json!(binary)
  defp normalize_payload(%_module{} = struct), do: Contracts.signable_map(struct)
  defp normalize_payload(map) when is_map(map), do: Contracts.signable_map(map)

  defp started_at_for_event("ledger_genesis", _event, existing), do: existing["started_at"]

  defp started_at_for_event(_event_type, event, existing),
    do: existing["started_at"] || fetch_field(event, :occurred_at)

  defp fetch_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp blank?(value), do: value in [nil, ""]

  defp sql_string(value) when is_binary(value), do: "'#{String.replace(value, "'", "''")}'"
  defp sql_nullable(nil), do: "NULL"
  defp sql_nullable(""), do: "NULL"
  defp sql_nullable(value) when is_binary(value), do: sql_string(value)
  defp sql_nullable_int(nil), do: "NULL"
  defp sql_nullable_int(value) when is_integer(value), do: Integer.to_string(value)
end
