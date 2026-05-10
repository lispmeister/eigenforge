defmodule Eigenforge.Contracts.NormalizedSnapshot do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.normalized_snapshot`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.normalized_snapshot"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :co2_ppm,
    :fan_state,
    :format_version,
    :freshness,
    :humidity_basis_points,
    :normalized_at,
    :room_id,
    :schema_id,
    :schema_version,
    :snapshot_hash,
    :snapshot_id,
    :snapshot_seq,
    :source_entity_ids,
    :source_observation_ids,
    :source_observed_at,
    :source_received_monotonic_ms,
    :source_received_seq,
    :source_status,
    :temperature_millicelsius
  ]
  @required_fields [
    :format_version,
    :schema_id,
    :schema_version,
    :snapshot_id,
    :snapshot_seq,
    :snapshot_hash,
    :room_id,
    :source_entity_ids,
    :source_observation_ids,
    :source_observed_at,
    :source_received_seq,
    :source_received_monotonic_ms,
    :source_status,
    :normalized_at,
    :freshness
  ]
  @field_types [
    co2_ppm: :integer,
    fan_state: :string,
    format_version: :string,
    freshness: :string,
    humidity_basis_points: :integer,
    normalized_at: :string,
    room_id: :string,
    schema_id: :string,
    schema_version: :integer,
    snapshot_hash: :string,
    snapshot_id: :string,
    snapshot_seq: :integer,
    source_entity_ids: :object,
    source_observation_ids: :object,
    source_observed_at: :object,
    source_received_monotonic_ms: :object,
    source_received_seq: :object,
    source_status: :object,
    temperature_millicelsius: :integer
  ]

  @enforce_keys []
  defstruct co2_ppm: nil,
            fan_state: nil,
            format_version: nil,
            freshness: nil,
            humidity_basis_points: nil,
            normalized_at: nil,
            room_id: nil,
            schema_id: nil,
            schema_version: nil,
            snapshot_hash: nil,
            snapshot_id: nil,
            snapshot_seq: nil,
            source_entity_ids: nil,
            source_observation_ids: nil,
            source_observed_at: nil,
            source_received_monotonic_ms: nil,
            source_received_seq: nil,
            source_status: nil,
            temperature_millicelsius: nil

  @type t :: %__MODULE__{
          co2_ppm: integer() | nil,
          fan_state: String.t() | nil,
          format_version: String.t() | nil,
          freshness: String.t() | nil,
          humidity_basis_points: integer() | nil,
          normalized_at: String.t() | nil,
          room_id: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          snapshot_hash: String.t() | nil,
          snapshot_id: String.t() | nil,
          snapshot_seq: integer() | nil,
          source_entity_ids: map() | nil,
          source_observation_ids: map() | nil,
          source_observed_at: map() | nil,
          source_received_monotonic_ms: map() | nil,
          source_received_seq: map() | nil,
          source_status: map() | nil,
          temperature_millicelsius: integer() | nil
        }

  def schema_id, do: @schema_id
  def schema_version, do: @schema_version
  def format_version, do: @format_version
  def fields, do: @fields
  def required_fields, do: @required_fields
  def field_types, do: @field_types

  def new(attrs), do: Eigenforge.Contracts.new(__MODULE__, attrs)
  def new!(attrs), do: Eigenforge.Contracts.new!(__MODULE__, attrs)
  def validate(value), do: Eigenforge.Contracts.validate(__MODULE__, value)
  def signable_map(value), do: Eigenforge.Contracts.signable_map(value)
  def canonical_json(value), do: Eigenforge.Contracts.canonical_json(signable_map(value))
  def payload_hash(value), do: Eigenforge.Contracts.payload_hash(value)
  def sign_hmac(value, secret), do: Eigenforge.Contracts.sign_hmac(value, secret)

  def verify_hmac(value, secret, signature),
    do: Eigenforge.Contracts.verify_hmac(value, secret, signature)
end
