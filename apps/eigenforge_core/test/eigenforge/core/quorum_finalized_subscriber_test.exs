defmodule Eigenforge.Core.QuorumFinalizedSubscriberTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerTooling
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.QuorumFinalizedSubscriber
  alias Eigenforge.Mailbox.ChannelManager

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-quorum-subscriber-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    db_path = Path.join(dir, "core.sqlite3")
    registry_name = Module.concat(__MODULE__, "MailboxRegistry#{System.unique_integer([:positive])}")
    subscriber_name =
      Module.concat(__MODULE__, "QuorumSubscriber#{System.unique_integer([:positive])}")
    writer_name = Module.concat(__MODULE__, "Writer#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: registry_name})

    start_supervised!(
      {LedgerWriter,
       db_path: db_path,
       core_node_id: "core_a",
       secret: "quorum-secret",
       name: writer_name}
    )

    start_supervised!(
      {QuorumFinalizedSubscriber,
       room_id: "placeholder",
       db_path: db_path,
       secret: "quorum-secret",
       writer: writer_name,
       mailbox_registry: registry_name,
       name: subscriber_name}
    )

    on_exit(fn -> File.rm_rf(dir) end)

    %{
      db_path: db_path,
      registry_name: registry_name
    }
  end

  test "persists quorum_finalized events with supporting votes", %{db_path: db_path, registry_name: registry_name} do
    evidence = %{
      "room_id" => "placeholder",
      "quorum_id" => "quorum-1",
      "consensus_decision_id" => "consensus-1",
      "idempotency_key" => "idem:v1:quorum-1",
      "target" => "actuator:fan",
      "requested_state" => "on",
      "decision" => "allow",
      "vote_count" => 2,
      "proposal_ids" => ["proposal-a", "proposal-b"],
      "core_node_ids" => ["core_a", "core_b"],
      "votes" => [
        %{
          "proposal_id" => "proposal-a",
          "core_node_id" => "core_a",
          "consensus_decision_id" => "consensus-1",
          "idempotency_key" => "idem:v1:quorum-1",
          "normalized_outcome" => "propose_action",
          "proposal_kind" => "action",
          "target" => "actuator:fan",
          "requested_state" => "on"
        },
        %{
          "proposal_id" => "proposal-b",
          "core_node_id" => "core_b",
          "consensus_decision_id" => "consensus-1",
          "idempotency_key" => "idem:v1:quorum-1",
          "normalized_outcome" => "propose_action",
          "proposal_kind" => "action",
          "target" => "actuator:fan",
          "requested_state" => "on"
        }
      ],
      "execution_status" => "executed",
      "published_at" => "2026-05-08T12:00:00.000Z"
    }

    assert wait_for_subscriber(registry_name)

    assert {:ok, 1} =
             ChannelManager.dispatch(
               "quorum_finalized:io",
               evidence,
               registry_name: registry_name
             )

    assert {:ok, rows} = wait_for_quorum_rows(db_path)

    assert length(rows) == 1
    [row] = rows
    assert row["event_type"] == "quorum_finalized"
    assert row["consensus_status"] == "quorum_finalized"

    quorum_ref = Contracts.decode_json!(row["quorum_ref"])
    payload = Contracts.decode_json!(row["payload"])

    assert quorum_ref["quorum_id"] == "quorum-1"
    assert payload["decision"] == "allow"

    assert :ok = LedgerTooling.verify(db_path, "core_a", "quorum-secret")
  end

  defp wait_for_quorum_rows(db_path, attempts \\ 20)

  defp wait_for_quorum_rows(db_path, 0) do
    LedgerSQLite.query_json(
      db_path,
      "SELECT event_type, consensus_status, quorum_ref, payload FROM ledger_events WHERE event_type = 'quorum_finalized' ORDER BY sequence ASC;"
    )
  end

  defp wait_for_quorum_rows(db_path, attempts) do
    case LedgerSQLite.query_json(
           db_path,
           "SELECT event_type, consensus_status, quorum_ref, payload FROM ledger_events WHERE event_type = 'quorum_finalized' ORDER BY sequence ASC;"
         ) do
      {:ok, []} ->
        Process.sleep(50)
        wait_for_quorum_rows(db_path, attempts - 1)

      result ->
        result
    end
  end

  defp wait_for_subscriber(registry_name, attempts \\ 40)

  defp wait_for_subscriber(_registry_name, 0), do: false

  defp wait_for_subscriber(registry_name, attempts) do
    if ChannelManager.subscriber_count("quorum_finalized:io", registry_name: registry_name) >= 1 do
      true
    else
      Process.sleep(50)
      wait_for_subscriber(registry_name, attempts - 1)
    end
  end
end
