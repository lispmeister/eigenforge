defmodule Eigenforge.Contracts.CapabilityCheck do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.capability_check`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.capability_check"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :action,
    :capability_check_id,
    :checked_at,
    :format_version,
    :grant_id,
    :reason,
    :result,
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
    :capability_check_id,
    :subject,
    :target,
    :action,
    :scope,
    :result,
    :reason,
    :checked_at
  ]
  @field_types [
    action: :string,
    capability_check_id: :string,
    checked_at: :string,
    format_version: :string,
    grant_id: :string,
    reason: :string,
    result: :string,
    schema_id: :string,
    schema_version: :integer,
    scope: :string,
    subject: :string,
    target: :string
  ]

  @enforce_keys []
  defstruct action: nil,
            capability_check_id: nil,
            checked_at: nil,
            format_version: nil,
            grant_id: nil,
            reason: nil,
            result: nil,
            schema_id: nil,
            schema_version: nil,
            scope: nil,
            subject: nil,
            target: nil

  @type t :: %__MODULE__{
          action: String.t() | nil,
          capability_check_id: String.t() | nil,
          checked_at: String.t() | nil,
          format_version: String.t() | nil,
          grant_id: String.t() | nil,
          reason: String.t() | nil,
          result: String.t() | nil,
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
