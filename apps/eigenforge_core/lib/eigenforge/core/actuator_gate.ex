defmodule Eigenforge.Core.ActuatorGate do
  @moduledoc """
  Gate between raw reasoner output and policy/capability evaluation.
  """

  alias Eigenforge.Contracts.ReasonerOutcome

  @idempotent_targets MapSet.new(["actuator:fan"])
  @unknown_states MapSet.new(["stale", "unknown", "malformed", "missing", "unavailable"])

  @spec gate(ReasonerOutcome.t(), term()) :: {:ok, ReasonerOutcome.t()}
  def gate(%ReasonerOutcome{outcome_type: "propose_action"} = reasoner, snapshot) do
    state = current_state(snapshot)

    cond do
      state in @unknown_states and not idempotent_target?(reasoner.target) ->
        {:ok,
         rewrite_outcome(
           reasoner,
           "propose_no_action",
           "Actuator state is unknown for a non-idempotent target; no action will be issued."
         )}

      state == reasoner.requested_state and idempotent_target?(reasoner.target) ->
        {:ok,
         rewrite_outcome(
           reasoner,
           "propose_no_action",
           idempotent_noop_reason(reasoner.requested_state)
         )}

      true ->
        {:ok, reasoner}
    end
  end

  def gate(%ReasonerOutcome{} = reasoner, _snapshot), do: {:ok, reasoner}

  defp rewrite_outcome(reasoner, outcome_type, reason) do
    %{reasoner | outcome_type: outcome_type, reason: reason}
  end

  defp current_state(snapshot), do: fan_state(snapshot)

  defp fan_state(%{fan_state: state}), do: state
  defp fan_state(%{"fan_state" => state}), do: state
  defp fan_state(_snapshot), do: nil

  defp idempotent_target?(target), do: MapSet.member?(@idempotent_targets, target)

  defp idempotent_noop_reason("on"),
    do: "Threshold reached but no action due to CO2 fan actuator already in state ON."

  defp idempotent_noop_reason("off"),
    do: "Threshold reached but no action due to CO2 fan actuator already in state OFF."

  defp idempotent_noop_reason(_requested_state),
    do: "Threshold reached but no action because the actuator is already in the requested state."
end
