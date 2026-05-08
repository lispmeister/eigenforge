defmodule Eigenforge.TraceTest do
  use ExUnit.Case, async: true

  @fixtures_dir "config/simulator_snapshots"
  @golden_dir "test/golden_traces"

  test "CO2 high with fan off issues command and records after-action" do
    trace = run!("co2_high_fan_off")

    assert step(trace, "reasoner_outcome") == "propose_action"
    assert step(trace, "capability_check") == "allow"
    assert step(trace, "policy_decision") == "allow"
    assert step(trace, "command_envelope") == "issued"
    assert step(trace, "delivery_receipt") == "issued"
    assert step(trace, "after_action") == "confirmed_changed"

    assert [%{"requested_state" => "on"}] = trace["command_envelopes"]
    assert [%{"status" => "confirmed_changed", "observed_state" => "on"}] = trace["after_actions"]
    assert Enum.any?(trace["ledger_events"], &(&1["event_type"] == "command_envelope_issued"))
  end

  test "CO2 high with fan already on records no-action and no command" do
    trace = run!("co2_high_fan_on")

    assert step(trace, "reasoner_outcome") == "propose_no_action"
    assert step(trace, "policy_decision") == "allow"
    assert step(trace, "command_envelope") == "not_delivered"

    assert trace["command_envelopes"] == []
    assert trace["delivery_receipts"] == []
    refute Enum.any?(trace["ledger_events"], &(&1["event_type"] == "command_envelope_issued"))
  end

  test "stale CO2 denies action and records stale deny event" do
    trace = run!("co2_stale_fan_off")

    assert step(trace, "reasoner_outcome") == "insufficient_fresh_data"
    assert step(trace, "policy_decision") == "deny_stale_snapshot"
    assert step(trace, "command_envelope") == "not_delivered"

    assert trace["command_envelopes"] == []
    assert Enum.any?(trace["ledger_events"], &(&1["event_type"] == "stale_snapshot_denied"))
  end

  test "committed golden traces verify" do
    for name <- ["co2_high_fan_off", "co2_high_fan_on", "co2_stale_fan_off"] do
      assert :ok = Eigenforge.Trace.verify_file(Path.join(@golden_dir, "#{name}.json"))
    end
  end

  defp run!(name) do
    fixture = Path.join(@fixtures_dir, "#{name}.json")
    golden = Path.join(@golden_dir, "#{name}.json")

    assert {:ok, trace} = Eigenforge.Trace.run_file(fixture)
    assert Eigenforge.Contracts.canonical_json(trace) == String.trim(File.read!(golden))

    trace
  end

  defp step(trace, name) do
    trace["steps"]
    |> Enum.find(&(&1["name"] == name))
    |> Map.fetch!("result")
  end
end
