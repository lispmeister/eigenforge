defmodule Eigenforge.IO.SnapshotNormalizerTest do
  use ExUnit.Case, async: true

  alias Eigenforge.IO.SnapshotNormalizer

  @entity_ids %{
    "co2" => "sensor.placeholder_co2",
    "humidity" => "sensor.placeholder_humidity",
    "temperature" => "sensor.placeholder_temperature",
    "fan" => "switch.placeholder_fan"
  }

  test "normalizes Home Assistant entity state into a V1 snapshot" do
    states = %{
      "sensor.placeholder_co2" => %{
        "entity_id" => "sensor.placeholder_co2",
        "entity_class" => "sensor",
        "state" => "1200",
        "observation_id" => "co2-1",
        "observed_at" => "2026-05-10T12:00:00.000Z",
        "received_seq" => 10,
        "received_monotonic_ms" => 100,
        "status" => "fresh"
      },
      "sensor.placeholder_humidity" => %{
        "entity_id" => "sensor.placeholder_humidity",
        "entity_class" => "sensor",
        "state" => "45.0",
        "observation_id" => "humidity-1",
        "observed_at" => "2026-05-10T12:00:00.000Z",
        "received_seq" => 10,
        "received_monotonic_ms" => 100,
        "status" => "fresh"
      },
      "sensor.placeholder_temperature" => %{
        "entity_id" => "sensor.placeholder_temperature",
        "entity_class" => "sensor",
        "state" => "22.0",
        "observation_id" => "temperature-1",
        "observed_at" => "2026-05-10T12:00:00.000Z",
        "received_seq" => 10,
        "received_monotonic_ms" => 100,
        "status" => "fresh"
      },
      "switch.placeholder_fan" => %{
        "entity_id" => "switch.placeholder_fan",
        "entity_class" => "switch",
        "state" => "off",
        "observation_id" => "fan-1",
        "observed_at" => "2026-05-10T12:00:00.000Z",
        "received_seq" => 10,
        "received_monotonic_ms" => 100,
        "status" => "fresh"
      }
    }

    assert {:ok, snapshot} =
             SnapshotNormalizer.normalize(@entity_ids, states,
               room_id: "placeholder",
               snapshot_id: "ha-1",
               snapshot_seq: 10,
               normalized_at: "2026-05-10T12:00:01.000Z"
             )

    assert snapshot.snapshot_id == "ha-1"
    assert snapshot.co2_ppm == 1200
    assert snapshot.humidity_basis_points == 4500
    assert snapshot.temperature_millicelsius == 22_000
    assert snapshot.fan_state == "off"
  end

  test "rejects missing or wrong-class entities" do
    bad_states = %{
      "sensor.placeholder_co2" => %{"entity_id" => "sensor.placeholder_co2", "entity_class" => "switch"},
      "sensor.placeholder_humidity" => %{"entity_id" => "sensor.placeholder_humidity", "entity_class" => "sensor"},
      "sensor.placeholder_temperature" => %{"entity_id" => "sensor.placeholder_temperature", "entity_class" => "sensor"}
    }

    assert {:error, errors} =
             SnapshotNormalizer.normalize(@entity_ids, bad_states,
               room_id: "placeholder",
               snapshot_id: "ha-bad",
               snapshot_seq: 1,
               normalized_at: "2026-05-10T12:00:01.000Z"
             )

    assert {:wrong_entity_class, "co2", "sensor.placeholder_co2", "sensor", "switch"} in errors
    assert {:missing_entity, "fan", "switch.placeholder_fan"} in errors
  end
end
