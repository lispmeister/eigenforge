defmodule Eigenforge.Core.LedgerWriterTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerTooling
  alias Eigenforge.Core.LedgerWriter

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ledger-writer-#{System.unique_integer([:positive])}.sqlite3"
      )

    on_exit(fn ->
      File.rm(db_path)
      File.rm("#{db_path}-wal")
      File.rm("#{db_path}-shm")
    end)

    %{db_path: db_path, secret: "ledger-writer-secret", core_node_id: "core_a"}
  end

  test "serializes concurrent append requests through one writer", %{
    db_path: db_path,
    secret: secret,
    core_node_id: core_node_id
  } do
    {:ok, pid} =
      start_supervised(
        {LedgerWriter, db_path: db_path, core_node_id: core_node_id, secret: secret, name: nil}
      )

    results =
      1..10
      |> Task.async_stream(
        fn ordinal ->
          LedgerWriter.append(pid, %{
            event_type: "reasoner_outcome_recorded",
            consensus_decision_id: "decision-#{ordinal}",
            consensus_status: "single_core_finalized",
            correlation_id: "corr-#{ordinal}",
            subject: "core_rule_stub",
            source_app: "eigenforge_core",
            payload: %{
              "format_version" => "json-canonical-v1",
              "schema_id" => "eigenforge.reasoner_outcome",
              "schema_version" => 1,
              "reasoner_outcome_id" => "outcome-#{ordinal}",
              "reasoner_id" => "core_rule_stub",
              "reasoner_version" => "v1",
              "snapshot_id" => "snap-#{ordinal}",
              "snapshot_hash" => String.duplicate("a", 64),
              "outcome_type" => "no_threshold_event",
              "target" => "actuator:fan",
              "requested_state" => nil,
              "reason" => "test payload",
              "confidence_bps" => 10_000,
              "metadata" => %{}
            }
          })
        end,
        ordered: false,
        timeout: 5_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, fn
             {:ok, {:ok, _event}} -> true
             _other -> false
           end)

    assert {:ok, rows} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT sequence, event_type FROM ledger_events ORDER BY sequence ASC;"
             )

    assert Enum.map(rows, & &1["sequence"]) == Enum.to_list(1..11)
    assert hd(rows)["event_type"] == "ledger_genesis"
    assert Enum.drop(rows, 1) |> Enum.all?(&(&1["event_type"] == "reasoner_outcome_recorded"))
    assert :ok = LedgerTooling.verify(db_path, core_node_id, secret)
  end

  test "returns documented error tuple after repeated local sqlite failures", %{
    db_path: db_path,
    secret: secret,
    core_node_id: core_node_id
  } do
    {:ok, pid} =
      start_supervised(
        {LedgerWriter, db_path: db_path, core_node_id: core_node_id, secret: secret, name: nil}
      )

    assert {:ok, _event} =
             LedgerWriter.append(pid, %{
               event_id: "duplicate-event-id",
               event_type: "reasoner_outcome_recorded",
               consensus_decision_id: "decision-1",
               consensus_status: "single_core_finalized",
               subject: "core_rule_stub",
               source_app: "eigenforge_core",
               payload: %{
                 "format_version" => "json-canonical-v1",
                 "schema_id" => "eigenforge.reasoner_outcome",
                 "schema_version" => 1,
                 "reasoner_outcome_id" => "outcome-1",
                 "reasoner_id" => "core_rule_stub",
                 "reasoner_version" => "v1",
                 "snapshot_id" => "snap-1",
                 "snapshot_hash" => String.duplicate("b", 64),
                 "outcome_type" => "propose_action",
                 "target" => "actuator:fan",
                 "requested_state" => "on",
                 "reason" => "test payload",
                 "confidence_bps" => 10_000,
                 "metadata" => %{}
               }
             })

    assert {:error, :ledger_persistence_failed} =
             LedgerWriter.append(pid, %{
               event_id: "duplicate-event-id",
               event_type: "policy_decision_recorded",
               consensus_decision_id: "decision-2",
               consensus_status: "single_core_finalized",
               subject: "core_rule_stub",
               source_app: "eigenforge_core",
               payload: %{
                 "format_version" => "json-canonical-v1",
                 "schema_id" => "eigenforge.policy_decision",
                 "schema_version" => 1,
                 "policy_decision_id" => "policy-2",
                 "snapshot_id" => "snap-2",
                 "snapshot_hash" => String.duplicate("c", 64),
                 "reasoner_outcome_id" => "outcome-2",
                 "subject" => "core_rule_stub",
                 "target" => "actuator:fan",
                 "action" => "command_actuator",
                 "scope" => "room:placeholder",
                 "requested_state" => "on",
                 "decision" => "allow",
                 "capability_grant_id" => "cap-core-rule-stub-fan",
                 "capability_status" => "allow",
                 "reason" => "test payload",
                 "decided_at" => "2026-05-10T12:00:00.000Z",
                 "metadata" => %{}
               }
             })
  end

  test "rolls back the ledger transaction if projection update fails mid-append", %{
    db_path: db_path,
    secret: secret,
    core_node_id: core_node_id
  } do
    failing_name = Module.concat(__MODULE__, "FailingWriter#{System.unique_integer([:positive])}")

    recovery_name =
      Module.concat(__MODULE__, "RecoveryWriter#{System.unique_integer([:positive])}")

    {:ok, failing_writer} =
      start_supervised(
        {LedgerWriter,
         db_path: db_path,
         core_node_id: core_node_id,
         secret: secret,
         append_hook: fn _event -> raise "inject projection failure" end,
         name: failing_name}
      )

    assert {:error, :ledger_persistence_failed} =
             LedgerWriter.append(failing_writer, %{
               event_type: "reasoner_outcome_recorded",
               consensus_decision_id: "decision-fail",
               consensus_status: "single_core_finalized",
               correlation_id: "corr-fail",
               subject: "core_rule_stub",
               source_app: "eigenforge_core",
               payload: %{
                 "format_version" => "json-canonical-v1",
                 "schema_id" => "eigenforge.reasoner_outcome",
                 "schema_version" => 1,
                 "reasoner_outcome_id" => "outcome-fail",
                 "reasoner_id" => "core_rule_stub",
                 "reasoner_version" => "v1",
                 "snapshot_id" => "snap-fail",
                 "snapshot_hash" => String.duplicate("d", 64),
                 "outcome_type" => "propose_action",
                 "target" => "actuator:fan",
                 "requested_state" => "on",
                 "reason" => "test payload",
                 "confidence_bps" => 10_000,
                 "metadata" => %{}
               }
             })

    assert {:ok, rows_after_failure} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT sequence, event_type FROM ledger_events ORDER BY sequence ASC;"
             )

    assert rows_after_failure == [%{"sequence" => 1, "event_type" => "ledger_genesis"}]

    :ok = GenServer.stop(failing_writer)

    {:ok, recovery_writer} =
      start_supervised(
        {LedgerWriter,
         db_path: db_path, core_node_id: core_node_id, secret: secret, name: recovery_name}
      )

    assert {:ok, _event} =
             LedgerWriter.append(recovery_writer, %{
               event_type: "reasoner_outcome_recorded",
               consensus_decision_id: "decision-recovered",
               consensus_status: "single_core_finalized",
               correlation_id: "corr-recovered",
               subject: "core_rule_stub",
               source_app: "eigenforge_core",
               payload: %{
                 "format_version" => "json-canonical-v1",
                 "schema_id" => "eigenforge.reasoner_outcome",
                 "schema_version" => 1,
                 "reasoner_outcome_id" => "outcome-recovered",
                 "reasoner_id" => "core_rule_stub",
                 "reasoner_version" => "v1",
                 "snapshot_id" => "snap-recovered",
                 "snapshot_hash" => String.duplicate("e", 64),
                 "outcome_type" => "no_threshold_event",
                 "reason" => "test payload",
                 "confidence_bps" => 10_000,
                 "metadata" => %{}
               }
             })

    assert {:ok, rows_after_recovery} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT sequence, event_type FROM ledger_events ORDER BY sequence ASC;"
             )

    assert Enum.map(rows_after_recovery, & &1["event_type"]) == [
             "ledger_genesis",
             "reasoner_outcome_recorded"
           ]
  end

  test "refuses to start when the existing hash chain is tampered", %{
    db_path: db_path,
    secret: secret,
    core_node_id: core_node_id
  } do
    previous_trap_exit = Process.flag(:trap_exit, true)

    on_exit(fn ->
      Process.flag(:trap_exit, previous_trap_exit)
    end)

    assert :ok = LedgerSQLite.init(db_path, core_node_id)
    assert :ok = LedgerTooling.ensure_genesis(db_path, core_node_id, secret)

    assert {:ok, _} =
             LedgerSQLite.query(db_path, "DROP TRIGGER ledger_events_no_update;")

    assert {:ok, _} =
             LedgerSQLite.query(
               db_path,
               "UPDATE ledger_events SET signature = 'tampered' WHERE sequence = 1;"
             )

    assert {:error, {"INV-12", {:bad_signature, 1}}} =
             LedgerWriter.start_link(
               db_path: db_path,
               core_node_id: core_node_id,
               secret: secret,
               name: nil
             )
  end

  test "ledger write paths do not use replace or conflict-update SQL" do
    writer_source =
      File.read!(Path.expand("../../../lib/eigenforge/core/ledger_writer.ex", __DIR__))

    sqlite_source =
      File.read!(Path.expand("../../../lib/eigenforge/core/ledger_sqlite.ex", __DIR__))

    refute writer_source =~ "INSERT OR REPLACE"
    refute writer_source =~ "ON CONFLICT"
    refute sqlite_source =~ "INSERT OR REPLACE"
    refute sqlite_source =~ "ON CONFLICT"
  end
end
