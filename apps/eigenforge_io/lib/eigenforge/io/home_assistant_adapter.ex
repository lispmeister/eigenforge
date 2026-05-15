defmodule Eigenforge.IO.HomeAssistantAdapter do
  @moduledoc """
  Pure V1 Home Assistant adapter helpers for validation, backoff, normalization,
  and fan command request construction.
  """

  alias Eigenforge.IO.SnapshotNormalizer

  @supported_sensor_keys ~w(co2 humidity temperature)
  @supported_fan_key "fan"

  @spec next_backoff_ms(non_neg_integer(), pos_integer()) :: pos_integer()
  def next_backoff_ms(attempt, max_ms) when is_integer(attempt) and attempt >= 0 and is_integer(max_ms) and max_ms > 0 do
    attempt
    |> then(fn n -> trunc(:math.pow(2, n) * 5_000) end)
    |> min(max_ms)
  end

  @spec dynamic_validate_entities(map(), map()) :: :ok | {:error, [term()]}
  def dynamic_validate_entities(entity_index, configured_ids)
      when is_map(entity_index) and is_map(configured_ids) do
    configured_ids = normalize_configured_ids(configured_ids)

    errors =
      []
      |> validate_expected_domains(entity_index, configured_ids, @supported_sensor_keys, "sensor")
      |> validate_expected_domains(entity_index, configured_ids, [@supported_fan_key], "switch")

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  @spec command_request(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def command_request(entity_id, "on") when is_binary(entity_id) do
    {:ok, %{"domain" => "switch", "service" => "turn_on", "entity_id" => entity_id}}
  end

  def command_request(entity_id, "off") when is_binary(entity_id) do
    {:ok, %{"domain" => "switch", "service" => "turn_off", "entity_id" => entity_id}}
  end

  def command_request(_entity_id, state), do: {:error, {:unsupported_requested_state, state}}

  @spec normalize_snapshot(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def normalize_snapshot(configured_ids, raw_states, opts \\ [])
      when is_map(configured_ids) and is_map(raw_states) do
    SnapshotNormalizer.normalize(configured_ids, raw_states, opts)
  end

  defp validate_expected_domains(errors, entity_index, configured_ids, keys, expected_domain) do
    Enum.reduce(keys, errors, fn key, acc ->
      entity_id = configured_ids[key]

      case Map.get(entity_index, entity_id) do
        nil ->
          [{:missing_entity, key, entity_id} | acc]

        %{"entity_id" => ^entity_id} = state ->
          actual_domain = entity_id |> String.split(".") |> hd()
          actual_class = Map.get(state, "entity_class")
          class_ok? = is_nil(actual_class) or actual_class == expected_domain

          if actual_domain == expected_domain and class_ok? do
            acc
          else
            [{:wrong_entity_class, key, entity_id, expected_domain, actual_class || actual_domain} | acc]
          end

        _ ->
          [{:missing_entity, key, entity_id} | acc]
      end
    end)
  end

  defp normalize_configured_ids(configured_ids) do
    Map.new(configured_ids, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
