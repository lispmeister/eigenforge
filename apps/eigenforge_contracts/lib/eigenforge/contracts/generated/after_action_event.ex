defmodule Eigenforge.Contracts.AfterActionEvent do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.after_action_event`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.after_action_event"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :adapter_attempt_id,
    :after_action_id,
    :command_id,
    :effect_key,
    :format_version,
    :idempotency_key,
    :observed_at,
    :observed_state,
    :reported_at,
    :requested_state,
    :schema_id,
    :schema_version,
    :source_fault_event_ids,
    :source_observation_ids,
    :status,
    :target
  ]
  @required_fields [
    :format_version,
    :schema_id,
    :schema_version,
    :after_action_id,
    :command_id,
    :idempotency_key,
    :effect_key,
    :target,
    :requested_state,
    :status,
    :observed_at,
    :reported_at
  ]
  @field_types [
    adapter_attempt_id: :string,
    after_action_id: :string,
    command_id: :string,
    effect_key: :string,
    format_version: :string,
    idempotency_key: :string,
    observed_at: :string,
    observed_state: :string,
    reported_at: :string,
    requested_state: :string,
    schema_id: :string,
    schema_version: :integer,
    source_fault_event_ids: :array,
    source_observation_ids: :array,
    status: :string,
    target: :string
  ]

  @enforce_keys []
  defstruct adapter_attempt_id: nil,
            after_action_id: nil,
            command_id: nil,
            effect_key: nil,
            format_version: nil,
            idempotency_key: nil,
            observed_at: nil,
            observed_state: nil,
            reported_at: nil,
            requested_state: nil,
            schema_id: nil,
            schema_version: nil,
            source_fault_event_ids: nil,
            source_observation_ids: nil,
            status: nil,
            target: nil

  @type t :: %__MODULE__{
          adapter_attempt_id: String.t() | nil,
          after_action_id: String.t() | nil,
          command_id: String.t() | nil,
          effect_key: String.t() | nil,
          format_version: String.t() | nil,
          idempotency_key: String.t() | nil,
          observed_at: String.t() | nil,
          observed_state: String.t() | nil,
          reported_at: String.t() | nil,
          requested_state: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          source_fault_event_ids: list() | nil,
          source_observation_ids: list() | nil,
          status: String.t() | nil,
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
