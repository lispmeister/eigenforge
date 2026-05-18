defmodule Eigenforge.TraceTest do
  use ExUnit.Case, async: false

  @repo_root Path.expand("../../../..", __DIR__)
  @fixtures_dir Path.join(@repo_root, "config/simulator_snapshots")
  @golden_dir Path.join(@repo_root, "test/golden_traces")

  test "CO2 high with fan off issues command and records after-action" do
    trace = run!("co2_high_fan_off")

    assert step(trace, "reasoner_outcome") == "propose_action"
    assert step(trace, "capability_check") == "allow"
    assert step(trace, "policy_decision") == "allow"
    assert step(trace, "finalized_decision") == "single_core_finalized"
    assert step(trace, "local_ledger_commit") == "committed"
    assert step(trace, "command_envelope") == "issued"
    assert step(trace, "delivery_receipt") == "issued"
    assert step(trace, "after_action") == "confirmed_changed"

    assert [%{"requested_state" => "on"}] = trace["command_envelopes"]
    assert [%{"status" => "confirmed_changed", "observed_state" => "on"}] = trace["after_actions"]

    assert_event_types(trace, [
      "reasoner_outcome_recorded",
      "capability_check_recorded",
      "policy_decision_recorded",
      "command_envelope_issued",
      "after_action_recorded"
    ])

    assert_local_sqlite_consensus(trace)
  end

  test "CO2 high with fan already on records no-action and no command" do
    trace = run!("co2_high_fan_on")

    assert step(trace, "reasoner_outcome") == "propose_no_action"
    assert step(trace, "capability_check") == "not_checked"
    assert step(trace, "policy_decision") == "no_command"
    assert step(trace, "finalized_decision") == "single_core_finalized"
    assert step(trace, "local_ledger_commit") == "committed"
    assert step(trace, "command_envelope") == "not_delivered"

    assert trace["command_envelopes"] == []
    assert trace["delivery_receipts"] == []

    assert_event_types(trace, [
      "reasoner_outcome_recorded",
      "policy_decision_recorded"
    ])

    assert_local_sqlite_consensus(trace)
  end

  test "stale CO2 denies action and records stale deny event" do
    trace = run!("co2_stale_fan_off")

    assert step(trace, "reasoner_outcome") == "insufficient_fresh_data"
    assert step(trace, "capability_check") == "not_checked"
    assert step(trace, "policy_decision") == "deny_stale_snapshot"
    assert step(trace, "finalized_decision") == "single_core_finalized"
    assert step(trace, "local_ledger_commit") == "committed"
    assert step(trace, "command_envelope") == "not_delivered"

    assert trace["command_envelopes"] == []

    assert_event_types(trace, [
      "reasoner_outcome_recorded",
      "stale_snapshot_denied"
    ])

    assert_local_sqlite_consensus(trace)
  end

  test "low CO2 with fan already on issues a fan-off command" do
    trace = run_fixture_file!("co2_low_fan_on")

    assert step(trace, "reasoner_outcome") == "propose_action"
    assert step(trace, "policy_decision") == "allow"
    assert [%{"requested_state" => "off"}] = trace["command_envelopes"]

    assert_event_types(trace, [
      "reasoner_outcome_recorded",
      "capability_check_recorded",
      "policy_decision_recorded",
      "command_envelope_issued",
      "after_action_recorded"
    ])
  end

  test "fixture-backed nominal CO2 path records no-threshold decision without capability check" do
    trace = run_fixture_file!("co2_nominal_fan_off")

    assert step(trace, "reasoner_outcome") == "no_threshold_event"
    assert step(trace, "capability_check") == "not_checked"
    assert step(trace, "policy_decision") == "no_command"

    assert_event_types(trace, [
      "reasoner_outcome_recorded",
      "policy_decision_recorded"
    ])
  end

  test "malformed CO2 fixtures deny action without a command" do
    trace = run_fixture_file!("co2_malformed")

    assert step(trace, "capability_check") == "not_checked"
    assert step(trace, "policy_decision") == "deny_stale_snapshot"

    assert_event_types(trace, [
      "reasoner_outcome_recorded",
      "stale_snapshot_denied"
    ])
  end

  test "nominal CO2 path records no-threshold decision without capability check" do
    trace =
      run_fixture!(%{
        base_fixture()
        | "co2_ppm" => 700,
          "fan_state" => "off"
      })

    assert step(trace, "reasoner_outcome") == "no_threshold_event"
    assert step(trace, "capability_check") == "not_checked"
    assert step(trace, "policy_decision") == "no_command"

    assert_event_types(trace, [
      "reasoner_outcome_recorded",
      "policy_decision_recorded"
    ])
  end

  test "committed golden traces verify" do
    for name <- ["co2_high_fan_off", "co2_high_fan_on", "co2_stale_fan_off"] do
      assert :ok = Eigenforge.Trace.verify_file(Path.join(@golden_dir, "#{name}.json"))
    end
  end

  test "verify_file fails for tampered golden traces" do
    golden = Path.join(@golden_dir, "co2_high_fan_off.json")

    tampered = Path.join(@golden_dir, "tampered-co2_high_fan_off.json")

    on_exit(fn -> File.rm(tampered) end)

    golden
    |> File.read!()
    |> String.replace("\"signature\":\"", "\"signature\":\"0", global: false)
    |> then(&File.write!(tampered, &1))

    assert {:error, {"INV-14", :trace_mismatch}} = Eigenforge.Trace.verify_file(tampered)
  end

  test "run_file rejects unsupported simulator fixture schema versions" do
    invalid =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-invalid-fixture-#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(invalid) end)

    File.write!(
      invalid,
      ~s({"fixture_schema_id":"eigenforge.simulator_fixture","fixture_schema_version":2,"scenario_id":"bad-fixture","snapshot_id":"snap-bad","snapshot_seq":1,"room_id":"placeholder","co2_ppm":1200,"fan_state":"off","source_entity_ids":{},"source_observation_ids":{},"source_observed_at":{},"source_received_seq":{},"source_received_monotonic_ms":{},"source_status":{},"normalized_at":"2026-05-08T12:00:00.000Z","freshness":"fresh"})
    )

    assert {:error, {:unsupported_fixture_schema_version, 2}} = Eigenforge.Trace.run_file(invalid)
  end

  test "snapshot hash changes when receive ordering fields change" do
    first_trace = run_fixture!(base_fixture())

    second_trace =
      run_fixture!(%{
        base_fixture()
        | "source_received_seq" => %{
            "co2" => 1,
            "humidity" => 1,
            "temperature" => 1,
            "fan" => 2
          }
      })

    assert snapshot_hash(first_trace) != snapshot_hash(second_trace)
  end

  test "trace run can use a non-default core node id" do
    fixture = base_fixture()

    core_a_trace = run_fixture!(fixture)
    core_b_trace = run_fixture!(fixture, core_node_id: "core_b")

    assert core_a_trace["core_node_id"] == "core_a"
    assert core_b_trace["core_node_id"] == "core_b"

    assert hd(core_a_trace["command_envelopes"])["idempotency_key"] !=
             hd(core_b_trace["command_envelopes"])["idempotency_key"]

    assert_local_sqlite_consensus(core_b_trace, "core_b")
  end

  test "stale observe-only sensors do not block a fresh CO2 fan command" do
    trace =
      run_fixture!(%{
        base_fixture()
        | "source_status" => %{
            "co2" => "fresh",
            "humidity" => "stale",
            "temperature" => "malformed",
            "fan" => "fresh"
          }
      })

    assert step(trace, "reasoner_outcome") == "propose_action"
    assert step(trace, "policy_decision") == "allow"
    assert step(trace, "command_envelope") == "issued"
    assert step(trace, "capability_check") == "allow"

    assert_event_types(trace, [
      "reasoner_outcome_recorded",
      "capability_check_recorded",
      "policy_decision_recorded",
      "command_envelope_issued",
      "after_action_recorded"
    ])
  end

  test "malformed fan state does not block idempotent fan commands" do
    trace =
      run_fixture!(%{
        base_fixture()
        | "fan_state" => "malformed",
          "source_status" => %{
            "co2" => "fresh",
            "humidity" => "fresh",
            "temperature" => "fresh",
            "fan" => "malformed"
          }
      })

    assert step(trace, "reasoner_outcome") == "propose_action"
    assert step(trace, "policy_decision") == "allow"
    assert step(trace, "command_envelope") == "issued"
  end

  defp run!(name) do
    fixture = Path.join(@fixtures_dir, "#{name}.json")
    golden = Path.join(@golden_dir, "#{name}.json")

    assert {:ok, trace} = Eigenforge.Trace.run_file(fixture)
    assert trace["coverage"]["trace_ids"] == [trace_case_id(name)]

    assert trace["coverage"]["step_ids"] == [
             "OODA-V1-001",
             "OODA-V1-002",
             "OODA-V1-003",
             "OODA-V1-004",
             "OODA-V1-005",
             "OODA-V1-006",
             "OODA-V1-007",
             "OODA-V1-008"
           ]

    assert Eigenforge.Contracts.canonical_json(trace) == String.trim(File.read!(golden))

    trace
  end

  defp run_fixture_file!(name) do
    fixture = Path.join(@fixtures_dir, "#{name}.json")
    assert {:ok, trace} = Eigenforge.Trace.run_file(fixture)
    trace
  end

  defp run_fixture!(fixture, opts \\ []) do
    assert {:ok, trace} = Eigenforge.Trace.run(fixture, "inline-fixture", opts)
    trace
  end

  defp snapshot_hash(trace) do
    trace["ledger_events"]
    |> Enum.find(&(&1["event_type"] == "reasoner_outcome_recorded"))
    |> then(& &1["payload"]["snapshot_hash"])
  end

  defp assert_event_types(trace, expected_types) do
    assert Enum.map(trace["ledger_events"], & &1["event_type"]) == expected_types
  end

  defp base_fixture do
    %{
      "snapshot_id" => "snap-inline",
      "snapshot_seq" => 1,
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{
        "co2" => "sensor.placeholder_co2",
        "humidity" => "sensor.placeholder_humidity",
        "temperature" => "sensor.placeholder_temperature",
        "fan" => "switch.placeholder_fan"
      },
      "source_observation_ids" => %{
        "co2" => "obs-inline-co2",
        "humidity" => "obs-inline-humidity",
        "temperature" => "obs-inline-temperature",
        "fan" => "obs-inline-fan"
      },
      "source_observed_at" => %{
        "co2" => "2026-05-08T12:00:00.000Z",
        "humidity" => "2026-05-08T12:00:00.000Z",
        "temperature" => "2026-05-08T12:00:00.000Z",
        "fan" => "2026-05-08T12:00:00.000Z"
      },
      "source_received_seq" => %{
        "co2" => 1,
        "humidity" => 1,
        "temperature" => 1,
        "fan" => 1
      },
      "source_received_monotonic_ms" => %{
        "co2" => 0,
        "humidity" => 0,
        "temperature" => 0,
        "fan" => 0
      },
      "source_status" => %{
        "co2" => "fresh",
        "humidity" => "fresh",
        "temperature" => "fresh",
        "fan" => "fresh"
      },
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }
  end

  defp step(trace, name) do
    trace["steps"]
    |> Enum.find(&(&1["name"] == name))
    |> Map.fetch!("result")
  end

  defp assert_local_sqlite_consensus(trace, core_node_id \\ "core_a") do
    assert trace["core_node_id"] == core_node_id
    assert trace["ledger_backend"] == "local_sqlite"
    assert trace["consensus_status"] == "single_core_finalized"
    assert trace["verification"]["local_ledger_committed"]
    assert trace["verification"]["consensus_status_valid"]

    consensus_ids =
      trace["ledger_events"]
      |> Enum.map(& &1["consensus_decision_id"])
      |> Enum.uniq()

    assert [_one_consensus_decision] = consensus_ids

    assert Enum.all?(trace["ledger_events"], fn event ->
             event["core_node_id"] == core_node_id and
               event["consensus_status"] == "single_core_finalized" and
               event["quorum_ref"] == %{}
           end)
  end

  defp trace_case_id(name) do
    name
    |> String.upcase()
    |> String.replace("_", "-")
    |> then(&"TRACE-V1-#{&1}")
  end
end
