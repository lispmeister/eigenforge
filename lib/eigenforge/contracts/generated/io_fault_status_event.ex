defmodule Eigenforge.Contracts.IoFaultStatusEvent do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.io_fault_status_event`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.io_fault_status_event"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :event_id,
    :format_version,
    :message,
    :metadata,
    :observed_at,
    :room_id,
    :schema_id,
    :schema_version,
    :source,
    :status
  ]
  @required_fields [
    :format_version,
    :schema_id,
    :schema_version,
    :event_id,
    :room_id,
    :source,
    :status,
    :observed_at
  ]
  @field_types [
    event_id: :string,
    format_version: :string,
    message: :string,
    metadata: :object,
    observed_at: :string,
    room_id: :string,
    schema_id: :string,
    schema_version: :integer,
    source: :string,
    status: :string
  ]

  @enforce_keys []
  defstruct event_id: nil,
            format_version: nil,
            message: nil,
            metadata: nil,
            observed_at: nil,
            room_id: nil,
            schema_id: nil,
            schema_version: nil,
            source: nil,
            status: nil

  @type t :: %__MODULE__{
          event_id: String.t() | nil,
          format_version: String.t() | nil,
          message: String.t() | nil,
          metadata: map() | nil,
          observed_at: String.t() | nil,
          room_id: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          source: String.t() | nil,
          status: String.t() | nil
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
