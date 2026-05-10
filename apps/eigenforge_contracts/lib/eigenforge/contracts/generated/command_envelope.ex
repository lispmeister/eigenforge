defmodule Eigenforge.Contracts.CommandEnvelope do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.command_envelope`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.command_envelope"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :action,
    :capability_event_id,
    :command_id,
    :decision_event_id,
    :effect_key,
    :expires_at,
    :format_version,
    :idempotency_key,
    :issued_at,
    :payload_hash,
    :policy_decision_id,
    :reasoner_outcome_event_id,
    :requested_state,
    :schema_id,
    :schema_version,
    :scope,
    :signature,
    :signature_version,
    :snapshot_id,
    :snapshot_seq,
    :subject,
    :target
  ]
  @required_fields [
    :format_version,
    :schema_id,
    :schema_version,
    :command_id,
    :idempotency_key,
    :effect_key,
    :subject,
    :target,
    :action,
    :scope,
    :requested_state,
    :snapshot_id,
    :snapshot_seq,
    :decision_event_id,
    :reasoner_outcome_event_id,
    :capability_event_id,
    :policy_decision_id,
    :issued_at,
    :expires_at,
    :payload_hash,
    :signature_version,
    :signature
  ]
  @field_types [
    action: :string,
    capability_event_id: :string,
    command_id: :string,
    decision_event_id: :string,
    effect_key: :string,
    expires_at: :string,
    format_version: :string,
    idempotency_key: :string,
    issued_at: :string,
    payload_hash: :string,
    policy_decision_id: :string,
    reasoner_outcome_event_id: :string,
    requested_state: :string,
    schema_id: :string,
    schema_version: :integer,
    scope: :string,
    signature: :string,
    signature_version: :string,
    snapshot_id: :string,
    snapshot_seq: :integer,
    subject: :string,
    target: :string
  ]

  @enforce_keys []
  defstruct action: nil,
            capability_event_id: nil,
            command_id: nil,
            decision_event_id: nil,
            effect_key: nil,
            expires_at: nil,
            format_version: nil,
            idempotency_key: nil,
            issued_at: nil,
            payload_hash: nil,
            policy_decision_id: nil,
            reasoner_outcome_event_id: nil,
            requested_state: nil,
            schema_id: nil,
            schema_version: nil,
            scope: nil,
            signature: nil,
            signature_version: nil,
            snapshot_id: nil,
            snapshot_seq: nil,
            subject: nil,
            target: nil

  @type t :: %__MODULE__{
          action: String.t() | nil,
          capability_event_id: String.t() | nil,
          command_id: String.t() | nil,
          decision_event_id: String.t() | nil,
          effect_key: String.t() | nil,
          expires_at: String.t() | nil,
          format_version: String.t() | nil,
          idempotency_key: String.t() | nil,
          issued_at: String.t() | nil,
          payload_hash: String.t() | nil,
          policy_decision_id: String.t() | nil,
          reasoner_outcome_event_id: String.t() | nil,
          requested_state: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          scope: String.t() | nil,
          signature: String.t() | nil,
          signature_version: String.t() | nil,
          snapshot_id: String.t() | nil,
          snapshot_seq: integer() | nil,
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
