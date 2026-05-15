defmodule Eigenforge.IO.SnapshotNormalizer do
  @moduledoc """
  Shared normalization helpers for IO snapshot sources.
  """

  alias Eigenforge.Core.SnapshotBuilder
  alias Eigenforge.IO.HomeAssistantAdapter

  @spec normalize(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def normalize(configured_ids, raw_states, opts \\ [])
      when is_map(configured_ids) and is_map(raw_states) do
    configured_ids = normalize_configured_ids(configured_ids)
    room_id = Keyword.get(opts, :room_id, "placeholder")
    snapshot_id = Keyword.get(opts, :snapshot_id, "ha-snapshot-1")
    snapshot_seq = Keyword.get(opts, :snapshot_seq, 1)
    normalized_at = Keyword.get(opts, :normalized_at, "2026-05-11T00:00:00.000Z")

    with :ok <- HomeAssistantAdapter.dynamic_validate_entities(raw_states, configured_ids),
         {:ok, attrs} <-
           snapshot_attrs(
             configured_ids,
             raw_states,
             room_id,
             snapshot_id,
             snapshot_seq,
             normalized_at
           ),
         {:ok, snapshot} <- SnapshotBuilder.build(attrs) do
      {:ok, snapshot |> Map.from_struct() |> Map.drop([:__struct__])}
    end
  end

  defp snapshot_attrs(configured_ids, raw_states, room_id, snapshot_id, snapshot_seq, normalized_at) do
    co2 = fetch_entity!(raw_states, configured_ids["co2"])
    humidity = fetch_entity!(raw_states, configured_ids["humidity"])
    temperature = fetch_entity!(raw_states, configured_ids["temperature"])
    fan = fetch_entity!(raw_states, configured_ids["fan"])

    {:ok,
     %{
       "snapshot_id" => snapshot_id,
       "snapshot_seq" => snapshot_seq,
       "room_id" => room_id,
       "co2_ppm" => integer_state(co2),
       "humidity_basis_points" => humidity_to_basis_points(humidity),
       "temperature_millicelsius" => temperature_to_millicelsius(temperature),
       "fan_state" => fan_state(fan),
       "source_entity_ids" => configured_ids,
       "source_observation_ids" => observation_ids(configured_ids, raw_states),
       "source_observed_at" => observed_times(configured_ids, raw_states),
       "source_received_seq" => received_seq(configured_ids, raw_states),
       "source_received_monotonic_ms" => received_monotonic_ms(configured_ids, raw_states),
       "source_status" => source_status(configured_ids, raw_states),
       "normalized_at" => normalized_at,
       "freshness" => freshness(raw_states, configured_ids["co2"])
     }}
  rescue
    error in KeyError -> {:error, {:missing_entity_state, error.key}}
  end

  defp fetch_entity!(raw_states, entity_id), do: Map.fetch!(raw_states, entity_id)
  defp integer_state(%{"state" => value}) when is_integer(value), do: value
  defp integer_state(%{"state" => value}) when is_binary(value), do: String.to_integer(value)

  defp humidity_to_basis_points(%{"state" => value}) when is_integer(value), do: value * 100
  defp humidity_to_basis_points(%{"state" => value}) when is_float(value), do: round(value * 100)

  defp humidity_to_basis_points(%{"state" => value}) when is_binary(value),
    do: value |> String.to_float() |> then(&round(&1 * 100))

  defp temperature_to_millicelsius(%{"state" => value}) when is_integer(value), do: value * 1_000
  defp temperature_to_millicelsius(%{"state" => value}) when is_float(value), do: round(value * 1_000)

  defp temperature_to_millicelsius(%{"state" => value}) when is_binary(value),
    do: value |> String.to_float() |> then(&round(&1 * 1_000))

  defp fan_state(%{"state" => "on"}), do: "on"
  defp fan_state(%{"state" => "off"}), do: "off"
  defp fan_state(_), do: "unknown"

  defp observation_ids(configured_ids, raw_states) do
    Map.new(configured_ids, fn {key, entity_id} -> {key, raw_states[entity_id]["observation_id"]} end)
  end

  defp observed_times(configured_ids, raw_states) do
    Map.new(configured_ids, fn {key, entity_id} -> {key, raw_states[entity_id]["observed_at"]} end)
  end

  defp received_seq(configured_ids, raw_states) do
    Map.new(configured_ids, fn {key, entity_id} -> {key, raw_states[entity_id]["received_seq"]} end)
  end

  defp received_monotonic_ms(configured_ids, raw_states) do
    Map.new(configured_ids, fn {key, entity_id} -> {key, raw_states[entity_id]["received_monotonic_ms"]} end)
  end

  defp source_status(configured_ids, raw_states) do
    Map.new(configured_ids, fn {key, entity_id} -> {key, raw_states[entity_id]["status"] || "fresh"} end)
  end

  defp freshness(raw_states, co2_entity_id) do
    case get_in(raw_states, [co2_entity_id, "status"]) do
      "fresh" -> "fresh"
      _ -> "stale"
    end
  end

  defp normalize_configured_ids(configured_ids) do
    Map.new(configured_ids, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
