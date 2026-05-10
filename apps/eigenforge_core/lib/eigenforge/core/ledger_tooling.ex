defmodule Eigenforge.Core.LedgerTooling do
  @moduledoc """
  Genesis and verification helpers for the local V1 SQLite ledger.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.LedgerSQLite

  @signature_version "hmac-sha256-v1"
  @genesis_previous_hash "eigenforge-ledger-genesis-v1"
  @decision_chain_event_types MapSet.new(~w(
                                reasoner_outcome_recorded
                                capability_check_recorded
                                policy_decision_recorded
                                command_envelope_issued
                                after_action_recorded
                                stale_snapshot_denied
                              ))
  @all_event_types (
                     @decision_chain_event_types
                     |> MapSet.put("ledger_genesis")
                     |> MapSet.put("connection_status_observed")
                     |> MapSet.put("io_fault_observed")
                     |> MapSet.put("node_fault_observed")
                   )

  @spec ensure_genesis(String.t(), String.t(), binary()) :: :ok | {:error, term()}
  def ensure_genesis(db_path, core_node_id, secret)
      when is_binary(db_path) and is_binary(core_node_id) and is_binary(secret) do
    with :ok <- LedgerSQLite.init(db_path, core_node_id),
         {:ok, rows} <- LedgerSQLite.query_json(db_path, "SELECT sequence FROM ledger_events LIMIT 1;") do
      case rows do
        [] -> insert_genesis(db_path, core_node_id, secret)
        [%{"sequence" => 1}] -> :ok
        _ -> {:error, :ledger_not_empty}
      end
    end
  end

  @spec verify(String.t(), String.t(), binary()) :: :ok | {:error, term()}
  def verify(db_path, core_node_id, secret)
      when is_binary(db_path) and is_binary(core_node_id) and is_binary(secret) do
    with {:ok, rows} <- LedgerSQLite.query_json(db_path, "SELECT * FROM ledger_events ORDER BY sequence ASC;"),
         :ok <- verify_non_empty(rows),
         :ok <- verify_rows(rows, core_node_id, secret) do
      :ok
    end
  end

  defp insert_genesis(db_path, core_node_id, secret) do
    payload = %{
      "format_version" => "json-canonical-v1",
      "schema_id" => "eigenforge.ledger_event",
      "schema_version" => 1,
      "kind" => "ledger_genesis",
      "core_node_id" => core_node_id
    }

    event = %{
      "event_id" => "ledger-genesis-#{core_node_id}",
      "sequence" => 1,
      "event_type" => "ledger_genesis",
      "core_node_id" => core_node_id,
      "consensus_decision_id" => nil,
      "consensus_status" => nil,
      "quorum_ref" => %{},
      "causation_id" => nil,
      "correlation_id" => "ledger-genesis-#{core_node_id}",
      "subject" => "eigenforge_core",
      "source_app" => "eigenforge_core",
      "occurred_at" => now(),
      "observed_at" => now(),
      "persisted_at" => now(),
      "format_version" => "json-canonical-v1",
      "schema_id" => "eigenforge.ledger_event",
      "schema_version" => 1,
      "payload" => payload,
      "payload_hash" => Contracts.hash_canonical(payload),
      "previous_event_hash" => @genesis_previous_hash,
      "event_hash" => "",
      "signature_version" => @signature_version,
      "signature" => ""
    }

    event_hash = Contracts.hash_excluding(event, [:event_hash, :signature])
    unsigned = Map.put(event, "event_hash", event_hash)

    signature =
      Contracts.sign_hmac_excluding(
        unsigned,
        secret,
        [:signature],
        "eigenforge:v1:ledger_event"
      )

    sql = """
    INSERT INTO ledger_events (
      sequence, event_id, event_type, core_node_id, consensus_decision_id,
      consensus_status, quorum_ref, causation_id, correlation_id, subject,
      source_app, occurred_at, observed_at, persisted_at, format_version,
      schema_id, schema_version, payload, payload_hash, previous_event_hash,
      event_hash, signature_version, signature
    ) VALUES (
      1,
      #{sql_string(unsigned["event_id"])},
      'ledger_genesis',
      #{sql_string(core_node_id)},
      NULL,
      NULL,
      '{}',
      NULL,
      #{sql_string(unsigned["correlation_id"])},
      'eigenforge_core',
      'eigenforge_core',
      #{sql_string(unsigned["occurred_at"])},
      #{sql_string(unsigned["observed_at"])},
      #{sql_string(unsigned["persisted_at"])},
      'json-canonical-v1',
      'eigenforge.ledger_event',
      1,
      #{sql_string(Contracts.canonical_json(payload))},
      #{sql_string(unsigned["payload_hash"])},
      '#{@genesis_previous_hash}',
      #{sql_string(unsigned["event_hash"])},
      '#{@signature_version}',
      #{sql_string(signature)}
    );
    """

    case LedgerSQLite.query(db_path, sql) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_non_empty([]), do: {:error, :empty_ledger}
  defp verify_non_empty(_rows), do: :ok

  defp verify_rows(rows, core_node_id, secret) do
    rows
    |> Enum.with_index(1)
    |> Enum.reduce_while(@genesis_previous_hash, fn {row, expected_sequence}, previous_hash ->
      case verify_row(row, expected_sequence, previous_hash, core_node_id, secret) do
        :ok -> {:cont, row["event_hash"]}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      _last_hash -> :ok
    end
  end

  defp verify_row(row, expected_sequence, previous_hash, core_node_id, secret) do
    with :ok <- verify_equals(row["sequence"], expected_sequence, {:bad_sequence, row["sequence"]}),
         :ok <- verify_equals(row["core_node_id"], core_node_id, {:bad_core_node_id, row["core_node_id"]}),
         :ok <- verify_equals(row["previous_event_hash"], previous_hash, {:bad_previous_hash, row["sequence"]}),
         :ok <- verify_event_type(row["event_type"]),
         :ok <- verify_timestamp(row["occurred_at"]),
         :ok <- verify_timestamp(row["observed_at"]),
         :ok <- verify_timestamp(row["persisted_at"]),
         :ok <- verify_consensus(row),
         {:ok, payload} <- verify_payload_hash(row),
         :ok <- verify_payload_schema(row["event_type"], payload),
         :ok <- verify_event_hash(row),
         :ok <- verify_signature(row, secret) do
      :ok
    end
  end

  defp verify_event_type(event_type) do
    if MapSet.member?(@all_event_types, event_type),
      do: :ok,
      else: {:error, {:bad_event_type, event_type}}
  end

  defp verify_timestamp(timestamp) do
    case CanonicalTime.parse(timestamp) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, {:bad_timestamp, timestamp}}
    end
  end

  defp verify_consensus(row) do
    decision_event? = MapSet.member?(@decision_chain_event_types, row["event_type"])

    cond do
      row["quorum_ref"] != "{}" -> {:error, {:bad_quorum_ref, row["quorum_ref"]}}
      decision_event? and blank?(row["consensus_decision_id"]) -> {:error, :missing_consensus_decision_id}
      decision_event? and blank?(row["consensus_status"]) -> {:error, :missing_consensus_status}
      not decision_event? and row["event_type"] == "ledger_genesis" -> :ok
      true -> :ok
    end
  end

  defp verify_payload_hash(row) do
    payload = Contracts.decode_json!(row["payload"])

    case verify_equals(
           row["payload_hash"],
           Contracts.hash_canonical(payload),
           {:bad_payload_hash, row["sequence"]}
         ) do
      :ok -> {:ok, payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_payload_schema("ledger_genesis", %{
         "schema_id" => "eigenforge.ledger_event",
         "schema_version" => 1,
         "format_version" => "json-canonical-v1"
       }),
       do: :ok

  defp verify_payload_schema("reasoner_outcome_recorded", payload),
    do: verify_payload_contract(payload, "eigenforge.reasoner_outcome")

  defp verify_payload_schema("capability_check_recorded", payload),
    do: verify_payload_contract(payload, "eigenforge.capability_check")

  defp verify_payload_schema("policy_decision_recorded", payload),
    do: verify_payload_contract(payload, "eigenforge.policy_decision")

  defp verify_payload_schema("stale_snapshot_denied", payload),
    do: verify_payload_contract(payload, "eigenforge.policy_decision")

  defp verify_payload_schema("command_envelope_issued", payload),
    do: verify_payload_contract(payload, "eigenforge.command_envelope")

  defp verify_payload_schema("after_action_recorded", payload),
    do: verify_payload_contract(payload, "eigenforge.after_action_event")

  defp verify_payload_schema("connection_status_observed", payload),
    do: verify_payload_contract(payload, "eigenforge.io_fault_status_event")

  defp verify_payload_schema("io_fault_observed", payload),
    do: verify_payload_contract(payload, "eigenforge.io_fault_status_event")

  defp verify_payload_schema("node_fault_observed", payload),
    do: verify_payload_contract(payload, "eigenforge.io_fault_status_event")

  defp verify_payload_schema(_event_type, _payload), do: :ok

  defp verify_payload_contract(
         %{
           "schema_id" => expected_schema_id,
           "schema_version" => 1,
           "format_version" => "json-canonical-v1"
         },
         expected_schema_id
       ),
       do: :ok

  defp verify_payload_contract(payload, expected_schema_id) do
    {:error,
     {:bad_payload_schema,
      expected_schema_id,
      payload["schema_id"],
      payload["schema_version"],
      payload["format_version"]}}
  end

  defp verify_event_hash(row) do
    row_map = row_map(row)

    verify_equals(
      row["event_hash"],
      Contracts.hash_excluding(row_map, [:event_hash, :signature]),
      {:bad_event_hash, row["sequence"]}
    )
  end

  defp verify_signature(row, secret) do
    row_map = row_map(row)

    verify_equals(
      row["signature"],
      Contracts.sign_hmac_excluding(
        row_map,
        secret,
        [:signature],
        "eigenforge:v1:ledger_event"
      ),
      {:bad_signature, row["sequence"]}
    )
  end

  defp row_map(row) do
    %{
      "event_id" => row["event_id"],
      "sequence" => row["sequence"],
      "event_type" => row["event_type"],
      "core_node_id" => row["core_node_id"],
      "consensus_decision_id" => row["consensus_decision_id"],
      "consensus_status" => row["consensus_status"],
      "quorum_ref" => Contracts.decode_json!(row["quorum_ref"]),
      "causation_id" => row["causation_id"],
      "correlation_id" => row["correlation_id"],
      "subject" => row["subject"],
      "source_app" => row["source_app"],
      "occurred_at" => row["occurred_at"],
      "observed_at" => row["observed_at"],
      "persisted_at" => row["persisted_at"],
      "format_version" => row["format_version"],
      "schema_id" => row["schema_id"],
      "schema_version" => row["schema_version"],
      "payload" => Contracts.decode_json!(row["payload"]),
      "payload_hash" => row["payload_hash"],
      "previous_event_hash" => row["previous_event_hash"],
      "event_hash" => row["event_hash"],
      "signature_version" => row["signature_version"],
      "signature" => row["signature"]
    }
  end

  defp now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> CanonicalTime.format()
  end

  defp verify_equals(left, right, _error) when left == right, do: :ok
  defp verify_equals(_left, _right, error), do: {:error, error}

  defp blank?(value), do: value in [nil, ""]

  defp sql_string(value) when is_binary(value), do: "'#{String.replace(value, "'", "''")}'"
end
