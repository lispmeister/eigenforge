defmodule Eigenforge.Core.CommandIssuer do
  @moduledoc """
  V1 command envelope construction.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Contracts.PolicyDecision
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.TraceIdentity

  @format_version "json-canonical-v1"
  @core_node_id "core_a"
  @subject "core_rule_stub"
  @target "actuator:fan"
  @action "command_actuator"
  @scope "room:placeholder"
  @signature_version "hmac-sha256-v1"

  @type issue_opt ::
          {:core_node_id, String.t()}
          | {:consensus_decision_id, String.t()}
          | {:decision_event_id, String.t()}
          | {:reasoner_outcome_event_id, String.t()}
          | {:capability_event_id, String.t() | nil}
          | {:effect_epoch, String.t() | nil}

  @spec issue(ReasonerOutcome.t(), term(), PolicyDecision.t(), term(), binary(), [issue_opt()]) ::
          {:ok, CommandEnvelope.t()} | {:ok, nil}
  def issue(reasoner, capability, policy, snapshot, secret, opts \\ [])

  def issue(
        %ReasonerOutcome{outcome_type: "propose_action"} = reasoner,
        _capability,
        %PolicyDecision{decision: "allow"} = policy,
        snapshot,
        secret,
        opts
      ) do
    issued_at = timestamp()
    core_node_id = Keyword.get(opts, :core_node_id, @core_node_id)

    consensus_decision_id =
      Keyword.get_lazy(opts, :consensus_decision_id, fn ->
        TraceIdentity.stable_id("consensus", [snapshot.snapshot_id])
      end)

    base = %{
      command_id:
        TraceIdentity.stable_id("cmd", [snapshot.snapshot_id, reasoner.requested_state]),
      idempotency_key:
        idempotency_key(snapshot, reasoner, policy, consensus_decision_id, core_node_id),
      effect_key: effect_key(snapshot, reasoner, Keyword.get(opts, :effect_epoch)),
      subject: @subject,
      target: @target,
      action: @action,
      scope: @scope,
      requested_state: reasoner.requested_state,
      snapshot_id: snapshot.snapshot_id,
      snapshot_seq: snapshot.snapshot_seq,
      decision_event_id:
        Keyword.get_lazy(opts, :decision_event_id, fn ->
          TraceIdentity.stable_id("event", ["command_envelope_issued", snapshot.snapshot_id])
        end),
      reasoner_outcome_event_id:
        Keyword.get_lazy(opts, :reasoner_outcome_event_id, fn ->
          TraceIdentity.stable_id("event", ["reasoner_outcome_recorded", snapshot.snapshot_id])
        end),
      capability_event_id:
        Keyword.get_lazy(opts, :capability_event_id, fn ->
          TraceIdentity.stable_id("event", ["capability_check_recorded", snapshot.snapshot_id])
        end),
      policy_decision_id: policy.policy_decision_id,
      issued_at: issued_at,
      expires_at: CanonicalTime.add_ms(issued_at, 5000),
      payload_hash: "",
      signature_version: @signature_version,
      signature: ""
    }

    payload_hash = Contracts.hash_excluding(base, [:payload_hash, :signature])
    unsigned = %{base | payload_hash: payload_hash}

    signature =
      Contracts.sign_hmac_excluding(
        unsigned,
        secret,
        [:signature],
        "eigenforge:v1:command_envelope"
      )

    {:ok, CommandEnvelope.new!(%{unsigned | signature: signature})}
  end

  def issue(_reasoner, _capability, _policy, _snapshot, _secret, _opts), do: {:ok, nil}

  defp idempotency_key(snapshot, reasoner, policy, consensus_decision_id, core_node_id) do
    payload = %{
      format_version: @format_version,
      core_node_id: core_node_id,
      room_id: snapshot.room_id,
      subject: @subject,
      target: @target,
      action: @action,
      scope: @scope,
      requested_state: reasoner.requested_state,
      snapshot_id: snapshot.snapshot_id,
      snapshot_hash: snapshot.snapshot_hash,
      reasoner_outcome_id: reasoner.reasoner_outcome_id,
      policy_decision_id: policy.policy_decision_id,
      consensus_decision_id: consensus_decision_id
    }

    "idem:v1:" <> Contracts.hash_canonical(payload)
  end

  defp effect_key(snapshot, reasoner, effect_epoch_override) do
    payload = %{
      format_version: @format_version,
      room_id: snapshot.room_id,
      target: @target,
      action: @action,
      requested_state: reasoner.requested_state,
      effect_epoch: effect_epoch(snapshot, effect_epoch_override)
    }

    "effect:v1:" <> Contracts.hash_canonical(payload)
  end

  defp effect_epoch(_snapshot, override) when is_binary(override) and override != "", do: override

  defp effect_epoch(snapshot, _override) do
    case map_get(snapshot, :latest_after_action_id) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        case map_get(snapshot.source_observation_ids, "fan") do
          value when is_binary(value) and value != "" -> value
          _ -> "startup"
        end
    end
  end

  defp map_get(map, key) when is_map(map) do
    case key do
      k when is_atom(k) ->
        Map.get(map, k) || Map.get(map, Atom.to_string(k))

      k when is_binary(k) ->
        atom_key =
          try do
            String.to_existing_atom(k)
          rescue
            ArgumentError -> nil
          end

        Map.get(map, k) || if(atom_key, do: Map.get(map, atom_key))
    end
  end

  defp timestamp, do: CanonicalTime.trace_start()
end
