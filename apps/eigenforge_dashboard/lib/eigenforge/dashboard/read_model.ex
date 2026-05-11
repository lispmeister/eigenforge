defmodule Eigenforge.Dashboard.ReadModel do
  @moduledoc """
  Read-only dashboard view builder over local projections and the ledger.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Core.LedgerProjections

  @spec snapshot(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def snapshot(db_path, room_id, opts \\ []) when is_binary(db_path) and is_binary(room_id) do
    limit = Keyword.get(opts, :limit, 10)

    with {:ok, room_state} <- latest_room_state(db_path, room_id),
         {:ok, recent_ledger_events} <- recent_ledger_events(db_path, room_id, limit),
         {:ok, recent_chains} <- recent_control_chains(db_path, room_id, limit),
         {:ok, recent_faults} <- recent_faults(db_path, room_id, limit) do
      {:ok,
       %{
         "room_id" => room_id,
         "io_mode" => room_state["io_mode"],
         "connection_status" => room_state["connection_status"] || "not_yet_observed",
         "simulator_mode" => room_state["io_mode"] == "simulator",
         "freshness" => room_state["freshness"],
         "stale_sensor_alert" => room_state["freshness"] == "stale",
         "sensor_state" => %{
           "co2_ppm" => room_state["co2_ppm"],
           "humidity_basis_points" => room_state["humidity_basis_points"],
           "temperature_millicelsius" => room_state["temperature_millicelsius"],
           "co2_status" => room_state["co2_status"],
           "humidity_status" => room_state["humidity_status"],
           "temperature_status" => room_state["temperature_status"]
         },
         "fan_state" => %{
           "state" => room_state["fan_state"],
           "status" => room_state["fan_status"]
         },
         "reasoner_outcome_id" => room_state["latest_reasoner_outcome_id"],
         "policy_decision_id" => room_state["latest_policy_decision_id"],
         "last_command_id" => room_state["latest_command_id"],
         "last_after_action_id" => room_state["latest_after_action_id"],
         "command_lifecycle" => room_state["command_lifecycle"] || "not_yet_observed",
         "recent_control_chains" => recent_chains,
         "recent_ledger_events" => recent_ledger_events,
         "recent_io_faults" => recent_faults
       }}
    end
  end

  defp latest_room_state(db_path, room_id) do
    case LedgerProjections.query_json(
           db_path,
           "SELECT * FROM latest_room_control_state WHERE room_id = #{sql_string(room_id)} LIMIT 1;"
         ) do
      {:ok, [row]} -> {:ok, row}
      {:ok, []} -> {:ok, %{"room_id" => room_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp recent_ledger_events(db_path, room_id, limit) do
    sql = """
    SELECT event_type, persisted_at, payload
    FROM ledger_events
    WHERE payload LIKE '%"room_id":"#{escape_like(room_id)}"%'
       OR payload LIKE '%"scope":"room:#{escape_like(room_id)}"%'
    ORDER BY sequence DESC
    LIMIT #{limit};
    """

    case LedgerProjections.query_json(db_path, sql) do
      {:ok, rows} ->
        {:ok,
         Enum.map(rows, fn row ->
           %{
             "event_type" => row["event_type"],
             "persisted_at" => row["persisted_at"],
             "payload" => Contracts.decode_json!(row["payload"])
           }
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recent_control_chains(db_path, room_id, limit) do
    LedgerProjections.query_json(
      db_path,
      """
      SELECT * FROM recent_control_chains
      WHERE room_id = #{sql_string(room_id)}
      ORDER BY updated_at DESC
      LIMIT #{limit};
      """
    )
  end

  defp recent_faults(db_path, room_id, limit) do
    sql = """
    SELECT event_type, persisted_at, payload
    FROM ledger_events
    WHERE event_type IN ('connection_status_observed', 'io_fault_observed', 'node_fault_observed')
      AND payload LIKE '%"room_id":"#{escape_like(room_id)}"%'
    ORDER BY sequence DESC
    LIMIT #{limit};
    """

    case LedgerProjections.query_json(db_path, sql) do
      {:ok, rows} ->
        {:ok,
         Enum.map(rows, fn row ->
           %{
             "event_type" => row["event_type"],
             "persisted_at" => row["persisted_at"],
             "payload" => Contracts.decode_json!(row["payload"])
           }
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sql_string(value), do: "'#{String.replace(value, "'", "''")}'"
  defp escape_like(value), do: value |> String.replace("\\", "\\\\") |> String.replace("'", "''")
end
