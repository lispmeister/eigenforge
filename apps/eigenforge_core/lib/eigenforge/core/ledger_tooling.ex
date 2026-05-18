defmodule Eigenforge.Core.LedgerTooling do
  @moduledoc """
  Genesis and verification helpers for the local V1 SQLite ledger.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.LedgerSQLite

  require Logger

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
  @all_event_types @decision_chain_event_types
                   |> MapSet.put("ledger_genesis")
                   |> MapSet.put("connection_status_observed")
                   |> MapSet.put("io_fault_observed")
                   |> MapSet.put("node_fault_observed")
                   |> MapSet.put("quorum_finalized")

  @spec ensure_genesis(String.t(), String.t(), binary()) :: :ok | {:error, term()}
  def ensure_genesis(db_path, core_node_id, secret)
      when is_binary(db_path) and is_binary(core_node_id) and is_binary(secret) do
    with :ok <- LedgerSQLite.init(db_path, core_node_id),
         {:ok, rows} <-
           LedgerSQLite.query_json(db_path, "SELECT sequence FROM ledger_events LIMIT 1;") do
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
    with {:ok, rows} <-
           LedgerSQLite.query_json(db_path, "SELECT * FROM ledger_events ORDER BY sequence ASC;"),
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

  defp verify_non_empty([]), do: {:error, inv("INV-13", :empty_ledger)}
  defp verify_non_empty(_rows), do: :ok

  defp verify_rows(rows, core_node_id, secret) do
    rows
    |> Enum.with_index(1)
    |> Enum.reduce_while(
      %{
        previous_hash: @genesis_previous_hash,
        seen_consensus_decision_ids: MapSet.new(),
        seen_idempotency_keys: MapSet.new()
      },
      fn {row, expected_sequence}, state ->
        case verify_row(row, expected_sequence, state, core_node_id, secret) do
          {:ok, next_state} -> {:cont, next_state}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:error, reason} -> {:error, reason}
      _state -> :ok
    end
  end

  defp verify_row(row, expected_sequence, state, core_node_id, secret) do
    previous_hash = state.previous_hash

    with :ok <-
           verify_equals(
             row["sequence"],
             expected_sequence,
             inv("INV-01", {:bad_sequence, row["sequence"]})
           ),
         :ok <-
           verify_equals(
             row["core_node_id"],
             core_node_id,
             inv("INV-02", {:bad_core_node_id, row["core_node_id"]})
           ),
         :ok <-
           verify_equals(
             row["previous_event_hash"],
             previous_hash,
             inv("INV-03", {:bad_previous_hash, row["sequence"]})
           ),
         :ok <- verify_event_type(row["event_type"]),
         :ok <- verify_timestamp(row["occurred_at"], "INV-05"),
         :ok <- verify_timestamp(row["observed_at"], "INV-06"),
         :ok <- verify_timestamp(row["persisted_at"], "INV-07"),
         :ok <- verify_consensus(row),
         {:ok, payload} <- verify_payload_hash(row),
         :ok <- verify_payload_schema(row["event_type"], payload),
         :ok <- verify_event_hash(row),
         :ok <- verify_signature(row, secret),
         :ok <- verify_quorum_finalized_uniqueness(row, payload, state) do
      {:ok, next_verify_state(row, payload, state)}
    end
  end

  defp verify_event_type(event_type) do
    if MapSet.member?(@all_event_types, event_type),
      do: :ok,
      else: {:error, inv("INV-04", {:bad_event_type, event_type})}
  end

  defp verify_timestamp(timestamp, inv_id) do
    case CanonicalTime.parse(timestamp) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, inv(inv_id, {:bad_timestamp, timestamp})}
    end
  end

  defp verify_consensus(row) do
    case row["event_type"] do
      "quorum_finalized" ->
        verify_quorum_consensus(row)

      _ ->
        decision_event? = MapSet.member?(@decision_chain_event_types, row["event_type"])

        cond do
          decision_event? and blank?(row["consensus_decision_id"]) ->
            {:error, inv("INV-08", :missing_consensus_decision_id)}

          decision_event? and blank?(row["consensus_status"]) ->
            {:error, inv("INV-08", :missing_consensus_status)}

          decision_event? and row["consensus_status"] == "single_core_finalized" ->
            :ok

          decision_event? and row["consensus_status"] == "quorum_finalized" ->
            Logger.warning(
              "INV-11 unsupported_consensus_status: #{row["consensus_status"]} (V1 single-core only)"
            )

          decision_event? ->
            {:error, inv("INV-11", {:unsupported_consensus_status, row["consensus_status"]})}

          row["event_type"] == "ledger_genesis" ->
            :ok

          true ->
            :ok
        end
    end
  end

  defp verify_quorum_consensus(row) do
    cond do
      blank?(row["consensus_decision_id"]) ->
        {:error, inv("INV-08", :missing_consensus_decision_id)}

      row["consensus_status"] != "quorum_finalized" ->
        {:error, inv("INV-14", {:unsupported_quorum_status, row["consensus_status"]})}

      blank_quorum_ref?(row["quorum_ref"]) ->
        {:error, inv("INV-14", :missing_quorum_ref)}

      true ->
        :ok
    end
  end

  defp verify_payload_hash(row) do
    payload = Contracts.decode_json!(row["payload"])

    case verify_equals(
           row["payload_hash"],
           Contracts.hash_canonical(payload),
           inv("INV-09", {:bad_payload_hash, row["sequence"]})
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

  defp verify_payload_schema("quorum_finalized", payload),
    do: verify_quorum_finalized_payload(payload)

  defp verify_payload_schema("connection_status_observed", payload),
    do: verify_payload_contract(payload, "eigenforge.io_fault_status_event")

  defp verify_payload_schema("io_fault_observed", payload),
    do: verify_payload_contract(payload, "eigenforge.io_fault_status_event")

  defp verify_payload_schema("node_fault_observed", payload),
    do: verify_payload_contract(payload, "eigenforge.io_fault_status_event")

  defp verify_payload_schema(_event_type, _payload), do: :ok

  defp verify_quorum_finalized_payload(%{
         "room_id" => _room_id,
         "quorum_id" => quorum_id,
         "consensus_decision_id" => consensus_decision_id,
         "idempotency_key" => idempotency_key,
         "target" => _target,
         "decision" => decision,
         "vote_count" => vote_count,
         "proposal_ids" => proposal_ids,
         "core_node_ids" => core_node_ids,
         "votes" => votes,
         "execution_status" => execution_status
       })
       when is_binary(quorum_id) and quorum_id != "" and
              is_binary(consensus_decision_id) and consensus_decision_id != "" and
              is_binary(idempotency_key) and idempotency_key != "" and
              decision in ["allow", "deny"] and
              is_integer(vote_count) and vote_count >= 2 and
              is_list(proposal_ids) and length(proposal_ids) >= 2 and
              is_list(core_node_ids) and length(core_node_ids) >= 2 and
              is_list(votes) and length(votes) >= 2 and
              execution_status in ["executed", "execution_failed", "not_executed"] do
    :ok
  end

  defp verify_quorum_finalized_payload(_payload),
    do: {:error, inv("INV-10", :invalid_quorum_finalized_payload)}

  defp verify_quorum_finalized_uniqueness(
         %{"event_type" => "quorum_finalized"} = row,
         payload,
         state
       ) do
    consensus_decision_id = row["consensus_decision_id"]
    idempotency_key = payload["idempotency_key"]

    cond do
      MapSet.member?(state.seen_consensus_decision_ids, consensus_decision_id) ->
        {:error, inv("INV-11", {:duplicate_finalized_decision, consensus_decision_id})}

      MapSet.member?(state.seen_idempotency_keys, idempotency_key) ->
        {:error, inv("INV-11", {:duplicate_idempotency_key, idempotency_key})}

      true ->
        :ok
    end
  end

  defp verify_quorum_finalized_uniqueness(_row, _payload, _state), do: :ok

  defp next_verify_state(%{"event_type" => "quorum_finalized"} = row, payload, state) do
    %{
      previous_hash: row["event_hash"],
      seen_consensus_decision_ids:
        MapSet.put(state.seen_consensus_decision_ids, row["consensus_decision_id"]),
      seen_idempotency_keys:
        MapSet.put(state.seen_idempotency_keys, payload["idempotency_key"])
    }
  end

  defp next_verify_state(row, _payload, state) do
    %{state | previous_hash: row["event_hash"]}
  end

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
     inv(
       "INV-10",
       {:bad_payload_schema, expected_schema_id, payload["schema_id"], payload["schema_version"],
        payload["format_version"]}
     )}
  end

  defp verify_event_hash(row) do
    row_map = row_map(row)

    verify_equals(
      row["event_hash"],
      Contracts.hash_excluding(row_map, [:event_hash, :signature]),
      inv("INV-11", {:bad_event_hash, row["sequence"]})
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
      inv("INV-12", {:bad_signature, row["sequence"]})
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

  defp inv(id, reason), do: {id, reason}

  defp blank?(value), do: value in [nil, ""]
  defp blank_quorum_ref?(%{} = quorum_ref), do: map_size(quorum_ref) == 0
  defp blank_quorum_ref?(value), do: blank?(value)

  defp sql_string(value) when is_binary(value), do: "'#{String.replace(value, "'", "''")}'"
end
