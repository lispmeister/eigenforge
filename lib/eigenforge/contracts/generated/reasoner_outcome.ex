defmodule Eigenforge.Contracts.ReasonerOutcome do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.reasoner_outcome`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.reasoner_outcome"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :confidence_bps,
    :format_version,
    :metadata,
    :outcome_type,
    :reason,
    :reasoner_id,
    :reasoner_version,
    :requested_state,
    :schema_id,
    :schema_version,
    :snapshot_hash,
    :snapshot_id,
    :target
  ]
  @required_fields [
    :format_version,
    :schema_id,
    :schema_version,
    :reasoner_id,
    :reasoner_version,
    :snapshot_id,
    :snapshot_hash,
    :outcome_type,
    :reason,
    :confidence_bps
  ]
  @field_types [
    confidence_bps: :integer,
    format_version: :string,
    metadata: :object,
    outcome_type: :string,
    reason: :string,
    reasoner_id: :string,
    reasoner_version: :string,
    requested_state: :string,
    schema_id: :string,
    schema_version: :integer,
    snapshot_hash: :string,
    snapshot_id: :string,
    target: :string
  ]

  @enforce_keys []
  defstruct confidence_bps: nil,
            format_version: nil,
            metadata: nil,
            outcome_type: nil,
            reason: nil,
            reasoner_id: nil,
            reasoner_version: nil,
            requested_state: nil,
            schema_id: nil,
            schema_version: nil,
            snapshot_hash: nil,
            snapshot_id: nil,
            target: nil

  @type t :: %__MODULE__{
          confidence_bps: integer() | nil,
          format_version: String.t() | nil,
          metadata: map() | nil,
          outcome_type: String.t() | nil,
          reason: String.t() | nil,
          reasoner_id: String.t() | nil,
          reasoner_version: String.t() | nil,
          requested_state: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          snapshot_hash: String.t() | nil,
          snapshot_id: String.t() | nil,
          target: String.t() | nil
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
