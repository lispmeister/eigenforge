defmodule Eigenforge.Core.CommandIssuerTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Contracts.PolicyDecision
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.CommandIssuer

  @secret "issuer-test-secret"

  test "derives v1 idempotency and effect keys from canonical payloads" do
    snapshot = snapshot("obs-fan-1")
    reasoner = reasoner(snapshot, "outcome-1")
    policy = policy(snapshot, reasoner, "policy-1")

    assert {:ok, command} = CommandIssuer.issue(reasoner, nil, policy, snapshot, @secret)

    assert String.starts_with?(command.idempotency_key, "idem:v1:")
    assert String.starts_with?(command.effect_key, "effect:v1:")
  end

  test "effect key falls back to startup when fan observation is missing" do
    snapshot_with_fan = snapshot("obs-fan-1")
    snapshot_without_fan = snapshot(nil)

    reasoner_with_fan = reasoner(snapshot_with_fan, "outcome-1")
    reasoner_without_fan = reasoner(snapshot_without_fan, "outcome-1")
    policy_with_fan = policy(snapshot_with_fan, reasoner_with_fan, "policy-1")
    policy_without_fan = policy(snapshot_without_fan, reasoner_without_fan, "policy-1")

    assert {:ok, command_with_fan} =
             CommandIssuer.issue(reasoner_with_fan, nil, policy_with_fan, snapshot_with_fan, @secret)

    assert {:ok, command_without_fan} =
             CommandIssuer.issue(
               reasoner_without_fan,
               nil,
               policy_without_fan,
               snapshot_without_fan,
               @secret
             )

    refute command_with_fan.effect_key == command_without_fan.effect_key
  end

  test "effect key can be seeded from a terminal after-action epoch when no fan observation is present" do
    snapshot = snapshot(nil)
    reasoner = reasoner(snapshot, "outcome-1")
    policy = policy(snapshot, reasoner, "policy-1")

    assert {:ok, startup_command} =
             CommandIssuer.issue(reasoner, nil, policy, snapshot, @secret)

    assert {:ok, terminal_command} =
             CommandIssuer.issue(reasoner, nil, policy, snapshot, @secret,
               effect_epoch: "after-action-1"
             )

    refute startup_command.effect_key == terminal_command.effect_key
  end

  test "distinct consensus decisions produce distinct idempotency keys" do
    snapshot = snapshot("obs-fan-1")
    reasoner = reasoner(snapshot, "outcome-1")
    policy = policy(snapshot, reasoner, "policy-1")

    assert {:ok, first_command} =
             CommandIssuer.issue(reasoner, nil, policy, snapshot, @secret,
               consensus_decision_id: "consensus-1"
             )

    assert {:ok, second_command} =
             CommandIssuer.issue(reasoner, nil, policy, snapshot, @secret,
               consensus_decision_id: "consensus-2"
             )

    refute first_command.idempotency_key == second_command.idempotency_key
  end

  test "the same finalized decision keeps the same idempotency key" do
    snapshot = snapshot("obs-fan-1")
    reasoner = reasoner(snapshot, "outcome-1")
    policy = policy(snapshot, reasoner, "policy-1")

    assert {:ok, first_command} =
             CommandIssuer.issue(reasoner, nil, policy, snapshot, @secret,
               consensus_decision_id: "consensus-1"
             )

    assert {:ok, second_command} =
             CommandIssuer.issue(reasoner, nil, policy, snapshot, @secret,
               consensus_decision_id: "consensus-1"
             )

    assert first_command.idempotency_key == second_command.idempotency_key
  end

  defp snapshot(fan_observation_id) do
    source_observation_ids =
      if fan_observation_id do
        %{"fan" => fan_observation_id}
      else
        %{}
      end

    NormalizedSnapshot.new!(%{
      snapshot_id: "snap-1",
      snapshot_seq: 1,
      snapshot_hash: String.duplicate("a", 64),
      room_id: "placeholder",
      co2_ppm: 1200,
      humidity_basis_points: 4500,
      temperature_millicelsius: 22_000,
      fan_state: "off",
      source_entity_ids: %{},
      source_observation_ids: source_observation_ids,
      source_observed_at: %{},
      source_received_seq: %{},
      source_received_monotonic_ms: %{},
      source_status: %{},
      normalized_at: "2026-05-08T12:00:00.000Z",
      freshness: "fresh"
    })
  end

  defp reasoner(snapshot, reasoner_outcome_id) do
    ReasonerOutcome.new!(%{
      reasoner_outcome_id: reasoner_outcome_id,
      reasoner_id: "core_rule_stub",
      reasoner_version: "v1",
      snapshot_id: snapshot.snapshot_id,
      snapshot_hash: snapshot.snapshot_hash,
      outcome_type: "propose_action",
      target: "actuator:fan",
      requested_state: "on",
      reason: "test",
      confidence_bps: 10_000,
      metadata: %{}
    })
  end

  defp policy(snapshot, reasoner, policy_decision_id) do
    PolicyDecision.new!(%{
      policy_decision_id: policy_decision_id,
      snapshot_id: snapshot.snapshot_id,
      snapshot_hash: snapshot.snapshot_hash,
      reasoner_outcome_id: reasoner.reasoner_outcome_id,
      subject: "core_rule_stub",
      target: "actuator:fan",
      action: "command_actuator",
      scope: "room:placeholder",
      requested_state: "on",
      decision: "allow",
      capability_grant_id: "cap-core-rule-stub-fan",
      capability_status: "allow",
      reason: "test",
      decided_at: "2026-05-08T12:00:00.000Z",
      metadata: %{}
    })
  end
end
