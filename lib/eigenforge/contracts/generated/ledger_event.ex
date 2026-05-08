defmodule Eigenforge.Contracts.LedgerEvent do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.ledger_event`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.ledger_event"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [:causation_id, :correlation_id, :event_hash, :event_id, :event_type, :format_version, :observed_at, :occurred_at, :payload, :payload_hash, :persisted_at, :previous_event_hash, :schema_id, :schema_version, :sequence, :signature, :signature_version, :source_app, :subject]
  @required_fields [:format_version, :schema_id, :schema_version, :event_id, :sequence, :event_type, :subject, :source_app, :occurred_at, :persisted_at, :payload, :payload_hash, :previous_event_hash, :event_hash, :signature_version, :signature]
  @field_types [causation_id: :string, correlation_id: :string, event_hash: :string, event_id: :string, event_type: :string, format_version: :string, observed_at: :string, occurred_at: :string, payload: :object, payload_hash: :string, persisted_at: :string, previous_event_hash: :string, schema_id: :string, schema_version: :integer, sequence: :integer, signature: :string, signature_version: :string, source_app: :string, subject: :string]

  @enforce_keys []
  defstruct [
    causation_id: nil,
    correlation_id: nil,
    event_hash: nil,
    event_id: nil,
    event_type: nil,
    format_version: nil,
    observed_at: nil,
    occurred_at: nil,
    payload: nil,
    payload_hash: nil,
    persisted_at: nil,
    previous_event_hash: nil,
    schema_id: nil,
    schema_version: nil,
    sequence: nil,
    signature: nil,
    signature_version: nil,
    source_app: nil,
    subject: nil
  ]

  @type t :: %__MODULE__{
          causation_id: String.t() | nil,
          correlation_id: String.t() | nil,
          event_hash: String.t() | nil,
          event_id: String.t() | nil,
          event_type: String.t() | nil,
          format_version: String.t() | nil,
          observed_at: String.t() | nil,
          occurred_at: String.t() | nil,
          payload: map() | nil,
          payload_hash: String.t() | nil,
          persisted_at: String.t() | nil,
          previous_event_hash: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          sequence: integer() | nil,
          signature: String.t() | nil,
          signature_version: String.t() | nil,
          source_app: String.t() | nil,
          subject: String.t() | nil
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
  def verify_hmac(value, secret, signature), do: Eigenforge.Contracts.verify_hmac(value, secret, signature)
end
