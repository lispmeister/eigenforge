defmodule Eigenforge.Core.PolicyEngineTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts.CapabilityCheck
  alias Eigenforge.Contracts.PolicyDecision
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.PolicyEngine

  test "covers the spec-required decision branches" do
    snapshot = %{
      snapshot_id: "snap-1",
      snapshot_hash: String.duplicate("a", 64),
      normalized_at: "2026-05-08T12:00:00.000Z"
    }

    assert decision(
             "deny_missing_capability",
             reasoner("propose_action", "actuator:fan", "propose fan on"),
             capability("deny_missing_capability"),
             snapshot
           )

    assert decision(
             "deny_invalid_capability",
             reasoner("propose_action", "actuator:fan", "propose fan on"),
             capability("deny_invalid_capability"),
             snapshot
           )

    assert decision(
             "deny_unknown_non_idempotent_actuator_state",
             reasoner(
               "propose_no_action",
               "actuator:fan",
               "already in a non-idempotent unknown state"
             ),
             nil,
             snapshot
           )

    assert decision(
             "deny_expired_command",
             reasoner("propose_action", "actuator:fan", "propose fan on",
               metadata: %{"command_expires_at" => "2026-05-08T11:59:59.000Z"}
             ),
             capability("allow"),
             snapshot
           )

    assert decision(
             "deny_unsupported_action",
             reasoner("propose_action", "actuator:toaster", "propose toast"),
             capability("allow"),
             snapshot
           )

    assert decision(
             "noop_stub",
             reasoner("propose_action", "actuator:light", "propose light on"),
             capability("allow"),
             snapshot
           )
  end

  defp decision(expected, reasoner, capability, snapshot) do
    assert {:ok, %PolicyDecision{decision: decision}} =
             PolicyEngine.decide(reasoner, capability, snapshot)

    decision == expected
  end

  defp reasoner(outcome_type, target, reason, opts \\ []) do
    ReasonerOutcome.new!(%{
      confidence_bps: 10_000,
      format_version: "json-canonical-v1",
      metadata: Keyword.get(opts, :metadata, %{}),
      outcome_type: outcome_type,
      reason: reason,
      reasoner_id: "core_rule_stub",
      reasoner_outcome_id: "reasoner-1",
      reasoner_version: "v1",
      requested_state: "on",
      snapshot_hash: String.duplicate("b", 64),
      snapshot_id: "snap-1",
      target: target
    })
  end

  defp capability(result) do
    CapabilityCheck.new!(%{
      action: "command_actuator",
      capability_check_id: "cap-1",
      checked_at: "2026-05-08T12:00:00.000Z",
      format_version: "json-canonical-v1",
      grant_id: "grant-1",
      reason: "test",
      result: result,
      scope: "room:placeholder",
      subject: "core_rule_stub",
      target: "actuator:fan"
    })
  end
end
