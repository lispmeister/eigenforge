defmodule Eigenforge.Core.PolicyEngine do
  @moduledoc """
  V1 policy decision stage.
  """

  alias Eigenforge.Contracts.PolicyDecision
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.TraceIdentity

  @subject "core_rule_stub"
  @target "actuator:fan"
  @action "command_actuator"
  @scope "room:placeholder"

  @spec decide(ReasonerOutcome.t(), term() | nil, term()) :: {:ok, PolicyDecision.t()}
  def decide(%ReasonerOutcome{outcome_type: "insufficient_fresh_data"} = reasoner, capability, snapshot) do
    decision(reasoner, capability, snapshot, "deny_stale_snapshot", "CO2 input is not fresh enough for actuation.")
  end

  def decide(%ReasonerOutcome{outcome_type: "propose_action"} = reasoner, capability, snapshot) do
    decision(reasoner, capability, snapshot, "allow", "Capability and policy allow idempotent fan command.")
  end

  def decide(reasoner, capability, snapshot) do
    decision(reasoner, capability, snapshot, "no_command", "No physical execution requested.")
  end

  defp decision(reasoner, capability, snapshot, decision, reason) do
    physical_action? = reasoner.outcome_type == "propose_action" and decision == "allow"

    {:ok,
     PolicyDecision.new!(%{
       policy_decision_id: TraceIdentity.stable_id("policy", [snapshot.snapshot_id, reasoner.outcome_type, decision]),
       snapshot_id: snapshot.snapshot_id,
       snapshot_hash: snapshot.snapshot_hash,
       reasoner_outcome_id: reasoner.reasoner_outcome_id,
       subject: @subject,
       target: reasoner.target || @target,
       action: @action,
       scope: @scope,
       requested_state: reasoner.requested_state,
       decision: decision,
       capability_grant_id: if(physical_action? and capability, do: capability.grant_id),
       capability_status: if(physical_action? and capability, do: capability.result, else: "not_checked"),
       reason: reason,
       decided_at: timestamp(),
       metadata: %{}
     })}
  end

  defp timestamp, do: CanonicalTime.trace_start()
end
