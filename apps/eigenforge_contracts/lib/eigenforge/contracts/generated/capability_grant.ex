defmodule Eigenforge.Contracts.CapabilityGrant do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.capability_grant`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.capability_grant"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :action,
    :format_version,
    :grant_id,
    :issued_at,
    :schema_id,
    :schema_version,
    :scope,
    :subject,
    :target
  ]
  @required_fields [
    :format_version,
    :schema_id,
    :schema_version,
    :grant_id,
    :subject,
    :target,
    :action,
    :scope,
    :issued_at
  ]
  @field_types [
    action: :string,
    format_version: :string,
    grant_id: :string,
    issued_at: :string,
    schema_id: :string,
    schema_version: :integer,
    scope: :string,
    subject: :string,
    target: :string
  ]

  @enforce_keys []
  defstruct action: nil,
            format_version: nil,
            grant_id: nil,
            issued_at: nil,
            schema_id: nil,
            schema_version: nil,
            scope: nil,
            subject: nil,
            target: nil

  @type t :: %__MODULE__{
          action: String.t() | nil,
          format_version: String.t() | nil,
          grant_id: String.t() | nil,
          issued_at: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          scope: String.t() | nil,
          subject: String.t() | nil,
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
