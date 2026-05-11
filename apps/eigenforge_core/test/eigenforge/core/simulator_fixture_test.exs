defmodule Eigenforge.Core.SimulatorFixtureTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
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

  test "rejects malformed fixture intents that do not name the affected source" do
    fixture = %{
      "fixture_schema_id" => "eigenforge.simulator_fixture",
      "fixture_schema_version" => 1,
      "scenario_id" => "co2_malformed_wrong_field",
      "fixture_intent" => %{"field" => "fan_state", "kind" => "malformed_value"},
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

    assert {:error, {:mismatched_malformed_fixture_intent, "fan_state"}} =
             SimulatorFixture.load(fixture)
  end

  test "validates all fixtures in a directory and rejects duplicate scenario ids" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-fixture-dir-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    first =
      fixture_with_scenario("duplicate-scenario")
      |> Contracts.canonical_json()

    second =
      fixture_with_scenario("duplicate-scenario")
      |> Map.put("snapshot_id", "snap-dup-2")
      |> Contracts.canonical_json()

    File.write!(Path.join(dir, "one.json"), first <> "\n")
    File.write!(Path.join(dir, "two.json"), second <> "\n")

    assert {:error, {:duplicate_scenario_id, "duplicate-scenario", path}} =
             SimulatorFixture.validate_directory(dir)

    assert String.ends_with?(path, "two.json")
  end

  defp fixture_with_scenario(scenario_id) do
    %{
      "fixture_schema_id" => "eigenforge.simulator_fixture",
      "fixture_schema_version" => 1,
      "scenario_id" => scenario_id,
      "snapshot_id" => "snap-dup-1",
      "snapshot_seq" => 1,
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{},
      "source_observed_at" => %{},
      "source_received_seq" => %{},
      "source_received_monotonic_ms" => %{},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }
  end
end
