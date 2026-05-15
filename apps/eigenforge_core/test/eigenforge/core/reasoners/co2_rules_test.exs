defmodule Eigenforge.Core.Reasoners.Co2RulesTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Core.Reasoners.Co2Rules

  test "high CO2 with fan off proposes turning the fan on" do
    assert {:ok, outcome} = Co2Rules.reason(snapshot(%{co2_ppm: 1200, fan_state: "off"}))

    assert outcome.outcome_type == "propose_action"
    assert outcome.target == "actuator:fan"
    assert outcome.requested_state == "on"
  end

  test "high CO2 with fan already on still proposes action before the gate" do
    assert {:ok, outcome} = Co2Rules.reason(snapshot(%{co2_ppm: 1200, fan_state: "on"}))

    assert outcome.outcome_type == "propose_action"
    assert outcome.requested_state == "on"
  end

  test "stale CO2 source status denies fresh-data reasoning" do
    assert {:ok, outcome} =
             Co2Rules.reason(
               snapshot(%{
                 co2_ppm: 1200,
                 fan_state: "off",
                 source_status: %{
                   "co2" => "stale",
                   "humidity" => "fresh",
                   "temperature" => "fresh",
                   "fan" => "fresh"
                 }
               })
             )

    assert outcome.outcome_type == "insufficient_fresh_data"
    assert outcome.target == nil
  end

  defp snapshot(overrides) do
    base = %{
      snapshot_id: "snap-1",
      snapshot_seq: 1,
      snapshot_hash: String.duplicate("a", 64),
      room_id: "placeholder",
      co2_ppm: 700,
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
    |> NormalizedSnapshot.new!()
  end
end
