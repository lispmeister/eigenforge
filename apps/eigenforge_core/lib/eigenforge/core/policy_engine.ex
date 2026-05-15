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
  @supported_targets MapSet.new(["actuator:fan"])
  @stub_targets MapSet.new(["actuator:light", "actuator:laser", "actuator:beeper"])

  @spec decide(ReasonerOutcome.t(), term() | nil, term()) :: {:ok, PolicyDecision.t()}
  def decide(%ReasonerOutcome{outcome_type: "insufficient_fresh_data"} = reasoner, capability, snapshot) do
    decision(reasoner, capability, snapshot, "deny_stale_snapshot", "CO2 input is not fresh enough for actuation.")
  end

  def decide(%ReasonerOutcome{outcome_type: "propose_no_action"} = reasoner, capability, snapshot) do
    case reasoner.reason do
      reason when is_binary(reason) ->
        if String.contains?(reason, "non-idempotent") do
          decision(
            reasoner,
            capability,
            snapshot,
            "deny_unknown_non_idempotent_actuator_state",
            reason
          )
        else
          decision(reasoner, capability, snapshot, "no_command", "No physical execution requested.")
        end

      _ ->
        decision(reasoner, capability, snapshot, "no_command", "No physical execution requested.")
    end
  end

  def decide(%ReasonerOutcome{outcome_type: "propose_action"} = reasoner, capability, snapshot) do
    cond do
      capability && capability.result == "deny_missing_capability" ->
        decision(
          reasoner,
          capability,
          snapshot,
          "deny_missing_capability",
          "No matching capability grant was found."
        )

      capability && capability.result == "deny_invalid_capability" ->
        decision(
          reasoner,
          capability,
          snapshot,
          "deny_invalid_capability",
          "A matching capability grant failed signature verification."
        )

      stub_target?(reasoner.target) ->
        decision(reasoner, capability, snapshot, "noop_stub", "Stub actuators are handled as no-op commands.")

      unsupported_action?(reasoner) ->
        decision(reasoner, capability, snapshot, "deny_unsupported_action", "Requested action is not supported by the target.")

      expired_command?(reasoner, snapshot) ->
        decision(reasoner, capability, snapshot, "deny_expired_command", "Command expiry elapsed before policy approval.")

      true ->
        decision(reasoner, capability, snapshot, "allow", "Capability and policy allow idempotent fan command.")
    end
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

  defp unsupported_action?(%ReasonerOutcome{target: target}) do
    is_binary(target) and not MapSet.member?(@supported_targets, target)
  end

  defp stub_target?(target), do: MapSet.member?(@stub_targets, target)

  defp expired_command?(%ReasonerOutcome{metadata: metadata}, snapshot) do
    expires_at =
      Map.get(metadata || %{}, "command_expires_at") ||
        Map.get(metadata || %{}, :command_expires_at)

    case expires_at do
      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, expires_dt, _offset} ->
            case snapshot_normalized_at(snapshot) do
              %DateTime{} = current_dt ->
                DateTime.compare(current_dt, expires_dt) == :gt

              _ ->
                false
            end

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp snapshot_normalized_at(%{normalized_at: normalized_at}) when is_binary(normalized_at) do
    case DateTime.from_iso8601(normalized_at) do
      {:ok, parsed, _offset} -> parsed
      _ -> nil
    end
  end

  defp snapshot_normalized_at(%{"normalized_at" => normalized_at}) when is_binary(normalized_at) do
    case DateTime.from_iso8601(normalized_at) do
      {:ok, parsed, _offset} -> parsed
      _ -> nil
    end
  end

  defp snapshot_normalized_at(_snapshot), do: nil

  defp timestamp, do: CanonicalTime.trace_start()
end
