defmodule Eigenforge.Contracts.DeviceInventory do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.device_inventory`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.device_inventory"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [:format_version, :rooms, :schema_id, :schema_version]
  @required_fields [:format_version, :schema_id, :schema_version, :rooms]
  @field_types [
    format_version: :string,
    rooms: :array,
    schema_id: :string,
    schema_version: :integer
  ]

  @enforce_keys []
  defstruct format_version: nil,
            rooms: nil,
            schema_id: nil,
            schema_version: nil

  @type t :: %__MODULE__{
          format_version: String.t() | nil,
          rooms: list() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil
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
