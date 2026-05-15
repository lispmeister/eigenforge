defmodule Eigenforge.Core.ActuatorGateTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.ActuatorGate

  test "rewrites redundant fan-on commands to no action" do
    reasoner =
      reasoner(%{
        outcome_type: "propose_action",
        target: "actuator:fan",
        requested_state: "on",
        reason: "CO2 threshold exceeded"
      })

    snapshot = snapshot(%{fan_state: "on"})

    assert {:ok, gated} = ActuatorGate.gate(reasoner, snapshot)
    assert gated.outcome_type == "propose_no_action"
    assert gated.requested_state == "on"
    assert gated.reason == "Threshold reached but no action due to CO2 fan actuator already in state ON."
  end

  test "passes through fan commands when the actuator state is unknown" do
    reasoner =
      reasoner(%{
        outcome_type: "propose_action",
        target: "actuator:fan",
        requested_state: "off",
        reason: "CO2 threshold cleared"
      })

    snapshot = snapshot(%{fan_state: "unknown"})

    assert {:ok, gated} = ActuatorGate.gate(reasoner, snapshot)
    assert gated.outcome_type == "propose_action"
    assert gated.reason == "CO2 threshold cleared"
  end

  defp reasoner(overrides) do
    base = %{
      reasoner_outcome_id: "reasoner-1",
      reasoner_id: "core_rule_stub",
      reasoner_version: "v1",
      snapshot_id: "snap-1",
      snapshot_hash: String.duplicate("a", 64),
      outcome_type: "propose_action",
      target: "actuator:fan",
      requested_state: "on",
      reason: "threshold exceeded",
      confidence_bps: 10000,
      metadata: %{}
    }

    base
    |> Map.merge(overrides)
    |> ReasonerOutcome.new!()
  end

  defp snapshot(overrides) do
    base = %{
      snapshot_id: "snap-1",
      snapshot_seq: 1,
      snapshot_hash: String.duplicate("a", 64),
      room_id: "placeholder",
      co2_ppm: 1200,
      humidity_basis_points: 4500,
      temperature_millicelsius: 22_000,
      fan_state: "off",
      source_entity_ids: %{},
      source_observation_ids: %{},
      source_observed_at: %{},
      source_received_seq: %{},
      source_received_monotonic_ms: %{},
      source_status: %{
        "co2" => "fresh",
        "humidity" => "fresh",
        "temperature" => "fresh",
        "fan" => "fresh"
      },
      normalized_at: "2026-05-08T12:00:00.000Z",
      freshness: "fresh"
    }

    base
    |> Map.merge(overrides)
    |> Eigenforge.Contracts.NormalizedSnapshot.new!()
  end
end
