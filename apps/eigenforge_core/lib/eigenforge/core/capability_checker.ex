defmodule Eigenforge.Core.CapabilityChecker do
  @moduledoc """
  V1 static capability check stage.
  """

  alias Eigenforge.Contracts.CapabilityCheck
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.TraceIdentity

  @subject "core_rule_stub"
  @target "actuator:fan"
  @action "command_actuator"
  @scope "room:placeholder"
  @grant_id "cap-core-rule-stub-fan"

  @spec check(ReasonerOutcome.t(), term()) :: {:ok, CapabilityCheck.t() | nil}
  def check(%ReasonerOutcome{outcome_type: "propose_action"} = reasoner, _snapshot) do
    {:ok,
     CapabilityCheck.new!(%{
       capability_check_id:
         TraceIdentity.stable_id("cap-check", [reasoner.snapshot_id, reasoner.requested_state]),
       subject: @subject,
       target: @target,
       action: @action,
       scope: @scope,
       grant_id: @grant_id,
       result: "allow",
       reason: "Valid static V1 grant allows fan command.",
       checked_at: timestamp()
     })}
  end

  def check(_reasoner, _snapshot), do: {:ok, nil}

  defp timestamp, do: CanonicalTime.trace_start()
end
