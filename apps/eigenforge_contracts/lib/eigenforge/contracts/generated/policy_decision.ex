defmodule Eigenforge.Contracts.PolicyDecision do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.policy_decision`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.policy_decision"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :action,
    :capability_grant_id,
    :capability_status,
    :decided_at,
    :decision,
    :format_version,
    :metadata,
    :policy_decision_id,
    :reason,
    :reasoner_outcome_id,
    :requested_state,
    :schema_id,
    :schema_version,
    :scope,
    :snapshot_hash,
    :snapshot_id,
    :subject,
    :target
  ]
  @required_fields [
    :format_version,
    :schema_id,
    :schema_version,
    :policy_decision_id,
    :snapshot_id,
    :snapshot_hash,
    :reasoner_outcome_id,
    :subject,
    :target,
    :action,
    :scope,
    :decision,
    :capability_status,
    :reason,
    :decided_at,
    :metadata
  ]
  @field_types [
    action: :string,
    capability_grant_id: :string,
    capability_status: :string,
    decided_at: :string,
    decision: :string,
    format_version: :string,
    metadata: :object,
    policy_decision_id: :string,
    reason: :string,
    reasoner_outcome_id: :string,
    requested_state: :string,
    schema_id: :string,
    schema_version: :integer,
    scope: :string,
    snapshot_hash: :string,
    snapshot_id: :string,
    subject: :string,
    target: :string
  ]

  @enforce_keys []
  defstruct action: nil,
            capability_grant_id: nil,
            capability_status: nil,
            decided_at: nil,
            decision: nil,
            format_version: nil,
            metadata: nil,
            policy_decision_id: nil,
            reason: nil,
            reasoner_outcome_id: nil,
            requested_state: nil,
            schema_id: nil,
            schema_version: nil,
            scope: nil,
            snapshot_hash: nil,
            snapshot_id: nil,
            subject: nil,
            target: nil

  @type t :: %__MODULE__{
          action: String.t() | nil,
          capability_grant_id: String.t() | nil,
          capability_status: String.t() | nil,
          decided_at: String.t() | nil,
          decision: String.t() | nil,
          format_version: String.t() | nil,
          metadata: map() | nil,
          policy_decision_id: String.t() | nil,
          reason: String.t() | nil,
          reasoner_outcome_id: String.t() | nil,
          requested_state: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          scope: String.t() | nil,
          snapshot_hash: String.t() | nil,
          snapshot_id: String.t() | nil,
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
