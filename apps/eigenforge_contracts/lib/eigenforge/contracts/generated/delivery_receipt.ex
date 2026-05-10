defmodule Eigenforge.Contracts.DeliveryReceipt do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.delivery_receipt`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.delivery_receipt"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :command_id,
    :decision_event_id,
    :delivered_at,
    :delivered_topic,
    :format_version,
    :ledger_event_hash,
    :ledger_sequence,
    :receipt_id,
    :schema_id,
    :schema_version,
    :signature,
    :signature_version
  ]
  @required_fields [
    :format_version,
    :schema_id,
    :schema_version,
    :receipt_id,
    :command_id,
    :decision_event_id,
    :ledger_sequence,
    :ledger_event_hash,
    :delivered_topic,
    :delivered_at,
    :signature_version,
    :signature
  ]
  @field_types [
    command_id: :string,
    decision_event_id: :string,
    delivered_at: :string,
    delivered_topic: :string,
    format_version: :string,
    ledger_event_hash: :string,
    ledger_sequence: :integer,
    receipt_id: :string,
    schema_id: :string,
    schema_version: :integer,
    signature: :string,
    signature_version: :string
  ]

  @enforce_keys []
  defstruct command_id: nil,
            decision_event_id: nil,
            delivered_at: nil,
            delivered_topic: nil,
            format_version: nil,
            ledger_event_hash: nil,
            ledger_sequence: nil,
            receipt_id: nil,
            schema_id: nil,
            schema_version: nil,
            signature: nil,
            signature_version: nil

  @type t :: %__MODULE__{
          command_id: String.t() | nil,
          decision_event_id: String.t() | nil,
          delivered_at: String.t() | nil,
          delivered_topic: String.t() | nil,
          format_version: String.t() | nil,
          ledger_event_hash: String.t() | nil,
          ledger_sequence: integer() | nil,
          receipt_id: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          signature: String.t() | nil,
          signature_version: String.t() | nil
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
