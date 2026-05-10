defmodule Eigenforge.Core.SimulatorFixtureTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.SimulatorFixture

  test "loads committed simulator fixture metadata and snapshot payload" do
    path = Path.expand("../../../../../config/simulator_snapshots/co2_high_fan_off.json", __DIR__)

    assert {:ok, %{scenario_id: "co2_high_fan_off", snapshot: snapshot, intent: nil}} =
             SimulatorFixture.load_file(path)

    assert snapshot["snapshot_id"] == "snap-co2-high-fan-off"
    assert is_binary(snapshot["snapshot_hash"])
    refute Map.has_key?(snapshot, "schema_id")
  end

  test "rejects malformed fixtures without declared intent" do
    fixture = %{
      "fixture_schema_id" => "eigenforge.simulator_fixture",
      "fixture_schema_version" => 1,
      "scenario_id" => "co2_malformed_missing_intent",
      "snapshot_id" => "snap-bad",
      "snapshot_seq" => 1,
      "room_id" => "placeholder",
      "co2_ppm" => nil,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{},
      "source_observed_at" => %{},
      "source_received_seq" => %{},
      "source_received_monotonic_ms" => %{},
      "source_status" => %{"co2" => "malformed"},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "stale"
    }

    assert {:error, :missing_malformed_fixture_intent} = SimulatorFixture.load(fixture)
  end
end
