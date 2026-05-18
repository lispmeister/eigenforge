defmodule Eigenforge.Contracts.SignedProposal do
  @moduledoc """
  Generated Eigenforge contract for `eigenforge.signed_proposal`.

  Regenerate with:

      elixir tools/generate_contracts.exs
  """

  @schema_id "eigenforge.signed_proposal"
  @schema_version 1
  @format_version "json-canonical-v1"
  @fields [
    :action,
    :consensus_decision_id,
    :core_node_id,
    :format_version,
    :idempotency_key,
    :issued_at,
    :normalized_outcome,
    :payload_hash,
    :policy_decision_id,
    :proposal_id,
    :proposal_kind,
    :reasoner_outcome_id,
    :requested_state,
    :schema_id,
    :schema_version,
    :scope,
    :signature,
    :signature_version,
    :snapshot_hash,
    :snapshot_id,
    :snapshot_seq,
    :subject,
    :target
  ]
  @required_fields [
    :format_version,
    :schema_id,
    :schema_version,
    :proposal_id,
    :proposal_kind,
    :normalized_outcome,
    :core_node_id,
    :consensus_decision_id,
    :snapshot_id,
    :snapshot_seq,
    :snapshot_hash,
    :subject,
    :target,
    :action,
    :scope,
    :requested_state,
    :idempotency_key,
    :issued_at,
    :reasoner_outcome_id,
    :policy_decision_id,
    :payload_hash,
    :signature_version,
    :signature
  ]
  @field_types [
    action: :string,
    consensus_decision_id: :string,
    core_node_id: :string,
    format_version: :string,
    idempotency_key: :string,
    issued_at: :string,
    normalized_outcome: :string,
    payload_hash: :string,
    policy_decision_id: :string,
    proposal_id: :string,
    proposal_kind: :string,
    reasoner_outcome_id: :string,
    requested_state: :string,
    schema_id: :string,
    schema_version: :integer,
    scope: :string,
    signature: :string,
    signature_version: :string,
    snapshot_hash: :string,
    snapshot_id: :string,
    snapshot_seq: :integer,
    subject: :string,
    target: :string
  ]

  @enforce_keys []
  defstruct action: nil,
            consensus_decision_id: nil,
            core_node_id: nil,
            format_version: nil,
            idempotency_key: nil,
            issued_at: nil,
            normalized_outcome: nil,
            payload_hash: nil,
            policy_decision_id: nil,
            proposal_id: nil,
            proposal_kind: nil,
            reasoner_outcome_id: nil,
            requested_state: nil,
            schema_id: nil,
            schema_version: nil,
            scope: nil,
            signature: nil,
            signature_version: nil,
            snapshot_hash: nil,
            snapshot_id: nil,
            snapshot_seq: nil,
            subject: nil,
            target: nil

  @type t :: %__MODULE__{
          action: String.t() | nil,
          consensus_decision_id: String.t() | nil,
          core_node_id: String.t() | nil,
          format_version: String.t() | nil,
          idempotency_key: String.t() | nil,
          issued_at: String.t() | nil,
          normalized_outcome: String.t() | nil,
          payload_hash: String.t() | nil,
          policy_decision_id: String.t() | nil,
          proposal_id: String.t() | nil,
          proposal_kind: String.t() | nil,
          reasoner_outcome_id: String.t() | nil,
          requested_state: String.t() | nil,
          schema_id: String.t() | nil,
          schema_version: integer() | nil,
          scope: String.t() | nil,
          signature: String.t() | nil,
          signature_version: String.t() | nil,
          snapshot_hash: String.t() | nil,
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
