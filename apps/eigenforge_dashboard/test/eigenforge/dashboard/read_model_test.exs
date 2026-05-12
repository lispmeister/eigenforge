defmodule Eigenforge.Dashboard.ReadModelTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.AfterActionEvent
  alias Eigenforge.Contracts.IoFaultStatusEvent
  alias Eigenforge.Contracts.PolicyDecision
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.LedgerProjections
  alias Eigenforge.Dashboard.ReadModel

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-dashboard-#{System.unique_integer([:positive])}.sqlite3"
      )

    writer =
      start_supervised!(
        {LedgerWriter, db_path: db_path, core_node_id: "core_a", secret: "dashboard-secret", name: nil}
      )

    on_exit(fn ->
      File.rm(db_path)
      File.rm("#{db_path}-wal")
      File.rm("#{db_path}-shm")
    end)

    %{db_path: db_path, writer: writer}
  end

  test "builds a read-only dashboard snapshot from projections and recent ledger events", %{
    db_path: db_path,
    writer: writer
  } do
    assert :ok =
             LedgerProjections.observe_snapshot(db_path, %{
               "snapshot_id" => "snap-1",
               "snapshot_hash" => String.duplicate("a", 64),
               "room_id" => "placeholder",
               "co2_ppm" => 1200,
               "humidity_basis_points" => 4500,
               "temperature_millicelsius" => 22_000,
               "fan_state" => "off",
               "source_status" => %{
                 "co2" => "fresh",
                 "humidity" => "fresh",
                 "temperature" => "fresh",
                 "fan" => "not_yet_observed"
               },
               "normalized_at" => "2026-05-10T12:00:00.000Z",
               "freshness" => "fresh"
             }, io_mode: "simulator")

    assert {:ok, _} =
             LedgerWriter.append(writer, %{
               event_type: "connection_status_observed",
               subject: "io_adapter",
               source_app: "eigenforge_core",
               payload:
                 Contracts.signable_map(
                     IoFaultStatusEvent.new!(%{
                     event_id: "fault-1",
                     room_id: "placeholder",
                     source: "simulator",
                     fault_type: "connection_up",
                     observed_at: "2026-05-10T12:00:00.000Z",
                     metadata: %{}
                   })
                 )
             })

    assert {:ok, view} = ReadModel.snapshot(db_path, "placeholder")
    assert view["simulator_mode"]
    assert view["connection_status"] == "connection_up"
    assert view["sensor_state"]["co2_ppm"] == 1200
    assert view["fan_state"]["status"] == "not_yet_observed"
    assert view["reasoner_outcome"] == "not_yet_observed"
    assert view["policy_decision"] == "not_yet_observed"
    assert view["after_action_status"] == "not_yet_observed"
    assert Enum.any?(view["recent_io_faults"], &(&1["payload"]["fault_type"] == "connection_up"))

    assert {:ok, count_rows} = LedgerSQLite.query_json(db_path, "SELECT count(*) FROM ledger_events;")
    assert [%{"count(*)" => count}] = count_rows
    assert count >= 2
  end

  test "redacts secrets from decoded ledger payloads before exposing dashboard state", %{
    db_path: db_path,
    writer: writer
  } do
    assert {:ok, _} =
             LedgerWriter.append(writer, %{
               event_type: "io_fault_observed",
               subject: "io_adapter",
               source_app: "eigenforge_core",
               payload: %{
                 "room_id" => "placeholder",
                 "fault_type" => "adapter_execution_failed",
                 "metadata" => %{
                   "HOME_ASSISTANT_TOKEN" => "ha-secret-token",
                   "detail" => "EIGENFORGE_HMAC_SECRET=dashboard-secret"
                 }
               }
             })

    assert {:ok, view} =
             ReadModel.snapshot(db_path, "placeholder",
               redaction_secrets: ["ha-secret-token", "dashboard-secret"]
             )

    [fault | _] = view["recent_io_faults"]
    assert get_in(fault, ["payload", "metadata", "HOME_ASSISTANT_TOKEN"]) == "[REDACTED]"
    assert get_in(fault, ["payload", "metadata", "detail"]) =~ "[REDACTED]"
  end

  test "surfaces semantic control-state summaries from recent control chains", %{
    db_path: db_path,
    writer: writer
  } do
    assert :ok =
             LedgerProjections.observe_snapshot(db_path, %{
               "snapshot_id" => "snap-2",
               "snapshot_hash" => String.duplicate("b", 64),
               "room_id" => "placeholder",
               "co2_ppm" => 1400,
               "humidity_basis_points" => 4500,
               "temperature_millicelsius" => 22_000,
               "fan_state" => "off",
               "source_status" => %{
                 "co2" => "fresh",
                 "humidity" => "fresh",
                 "temperature" => "fresh",
                 "fan" => "fresh"
               },
               "normalized_at" => "2026-05-10T12:00:00.000Z",
               "freshness" => "fresh"
             }, io_mode: "simulator")

    assert {:ok, reasoner_event} =
             LedgerWriter.append(writer, %{
               event_type: "reasoner_outcome_recorded",
               subject: "core_rule_stub",
               source_app: "eigenforge_core",
               consensus_decision_id: "consensus-1",
               consensus_status: "single_core_finalized",
               correlation_id: "corr-1",
               payload:
                 Contracts.signable_map(
                   ReasonerOutcome.new!(%{
                     reasoner_outcome_id: "outcome-1",
                     reasoner_id: "core_rule_stub",
                     reasoner_version: "v1",
                     snapshot_id: "snap-2",
                     snapshot_hash: String.duplicate("b", 64),
                     outcome_type: "propose_action",
                     target: "actuator:fan",
                     requested_state: "on",
                     reason: "test",
                     confidence_bps: 10_000,
                     metadata: %{}
                   })
                 )
             })

    assert {:ok, _policy_event} =
             LedgerWriter.append(writer, %{
               event_type: "policy_decision_recorded",
               subject: "core_rule_stub",
               source_app: "eigenforge_core",
               consensus_decision_id: "consensus-1",
               consensus_status: "single_core_finalized",
               correlation_id: "corr-1",
               payload:
                 Contracts.signable_map(
                   PolicyDecision.new!(%{
                     policy_decision_id: "policy-1",
                     snapshot_id: "snap-2",
                     snapshot_hash: String.duplicate("b", 64),
                     reasoner_outcome_id: "outcome-1",
                     subject: "core_rule_stub",
                     target: "actuator:fan",
                     action: "command_actuator",
                     scope: "room:placeholder",
                     requested_state: "on",
                     decision: "allow",
                     capability_grant_id: "grant-1",
                     capability_status: "allow",
                     reason: "test",
                     decided_at: "2026-05-10T12:00:01.000Z",
                     metadata: %{}
                   })
                 )
             })

    assert {:ok, _after_action_event} =
             LedgerWriter.append(writer, %{
               event_type: "after_action_recorded",
               subject: "core_rule_stub",
               source_app: "eigenforge_core",
               consensus_decision_id: "consensus-1",
               consensus_status: "single_core_finalized",
               correlation_id: "corr-1",
               payload:
                 Contracts.signable_map(
                   AfterActionEvent.new!(%{
                     after_action_id: "after-1",
                     command_id: "cmd-1",
                     idempotency_key: "idem-1",
                     effect_key: "effect-1",
                     adapter_attempt_id: "attempt-1",
                     target: "actuator:fan",
                     requested_state: "on",
                     observed_state: "on",
                     status: "confirmed_changed",
                     observed_at: "2026-05-10T12:00:02.000Z",
                     reported_at: "2026-05-10T12:00:02.000Z",
                     source_observation_ids: ["obs-1"],
                     source_fault_event_ids: []
                   })
                 )
             })

    assert {:ok, view} = ReadModel.snapshot(db_path, "placeholder")
    assert view["reasoner_outcome"] == "propose_action"
    assert view["policy_decision"] == "allow"
    assert view["after_action_status"] == "confirmed_changed"
    assert List.first(view["recent_control_chains"])["reasoner_outcome_id"] == reasoner_event.payload["reasoner_outcome_id"]
  end
end
