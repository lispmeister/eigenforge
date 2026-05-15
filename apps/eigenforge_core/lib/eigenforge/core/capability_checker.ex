defmodule Eigenforge.Core.CapabilityChecker do
  @moduledoc """
  V1 static capability check stage.
  """

  alias Eigenforge.Contracts.CapabilityCheck
  alias Eigenforge.Contracts.CapabilityGrant
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.SignedConfig
  alias Eigenforge.Core.TraceIdentity

  @subject "core_rule_stub"
  @target "actuator:fan"
  @action "command_actuator"
  @scope "room:placeholder"
  @persistent_key {__MODULE__, :capability_grants}

  @spec configure(map()) :: :ok
  def configure(grants) when is_map(grants) do
    :persistent_term.put(@persistent_key, grants)
    :ok
  end

  @spec clear() :: :ok
  def clear do
    :persistent_term.erase(@persistent_key)
    :ok
  end

  @spec check(ReasonerOutcome.t(), term()) :: {:ok, CapabilityCheck.t() | nil}
  def check(%ReasonerOutcome{outcome_type: "propose_action"} = reasoner, snapshot) do
    case lookup_capability(reasoner, snapshot) do
      {:ok, %CapabilityGrant{} = grant} ->
        {:ok,
         CapabilityCheck.new!(%{
           capability_check_id:
             TraceIdentity.stable_id("cap-check", [reasoner.snapshot_id, reasoner.requested_state]),
           subject: grant.subject,
           target: grant.target,
           action: grant.action,
           scope: grant.scope,
           grant_id: grant.grant_id,
           result: "allow",
           reason: "Valid static V1 grant allows fan command.",
           checked_at: timestamp()
         })}

      {:error, :missing} ->
        deny(reasoner, snapshot, "deny_missing_capability", "No matching capability grant was found.")

      {:error, :invalid} ->
        deny(
          reasoner,
          snapshot,
          "deny_invalid_capability",
          "A matching capability grant failed signature verification."
        )
    end
  end

  def check(_reasoner, _snapshot), do: {:ok, nil}

  defp deny(reasoner, _snapshot, result, reason) do
    {:ok,
     CapabilityCheck.new!(%{
       capability_check_id:
         TraceIdentity.stable_id("cap-check", [reasoner.snapshot_id, reasoner.requested_state]),
       subject: @subject,
       target: @target,
       action: @action,
       scope: @scope,
       grant_id: nil,
       result: result,
       reason: reason,
       checked_at: timestamp()
     })}
  end

  defp lookup_capability(reasoner, snapshot) do
    grants = configured_grants()

    case Map.get(grants, capability_lookup_key(reasoner, snapshot)) do
      %CapabilityGrant{} = grant -> {:ok, grant}
      {:invalid, %CapabilityGrant{}} -> {:error, :invalid}
      %{grant: %CapabilityGrant{}, valid?: false} -> {:error, :invalid}
      %{grant: %CapabilityGrant{} = grant} -> {:ok, grant}
      _ -> {:error, :missing}
    end
  end

  defp configured_grants do
    case :persistent_term.get(@persistent_key, :unset) do
      :unset ->
        case load_default_grants() do
          {:ok, grants} ->
            configure(grants)
            grants

          {:error, _reason} ->
            %{}
        end

      grants ->
        grants
    end
  end

  defp load_default_grants do
    with {:ok, %RuntimeConfig{} = config} <- RuntimeConfig.load(runtime_env()),
         {:ok, grants} <- SignedConfig.load_capability_grants(config) do
      {:ok, grants}
    end
  end

  defp runtime_env do
    Application.get_env(:eigenforge_core, :runtime_env, %{})
  end

  defp capability_lookup_key(%ReasonerOutcome{} = reasoner, snapshot) do
    {subject(), reasoner.target || @target, @action, scope(snapshot)}
  end

  defp subject, do: @subject
  defp scope(_snapshot), do: @scope

  defp timestamp, do: CanonicalTime.trace_start()
end
