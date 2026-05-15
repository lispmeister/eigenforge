defmodule Eigenforge.Core.CapabilityCheckerTest do
  use ExUnit.Case, async: false

  alias Eigenforge.Contracts.CapabilityGrant
  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.CapabilityChecker

  setup do
    CapabilityChecker.clear()

    on_exit(fn ->
      CapabilityChecker.clear()
    end)

    :ok
  end

  test "allows a configured static grant" do
    CapabilityChecker.configure(%{
      {"core_rule_stub", "actuator:fan", "command_actuator", "room:placeholder"} =>
        CapabilityGrant.new!(%{
          grant_id: "cap-core-rule-stub-actuator-fan-command-actuator-room-placeholder",
          subject: "core_rule_stub",
          target: "actuator:fan",
          action: "command_actuator",
          scope: "room:placeholder",
          issued_at: "2026-05-10T00:00:00.000Z"
        })
    })

    assert {:ok, check} = CapabilityChecker.check(reasoner(), snapshot())
    assert check.result == "allow"
    assert check.grant_id =~ "cap-core-rule-stub"
  end

  test "denies missing capability when no matching grant exists" do
    CapabilityChecker.configure(%{})

    assert {:ok, check} = CapabilityChecker.check(reasoner(), snapshot())
    assert check.result == "deny_missing_capability"
  end

  test "denies invalid capability entries" do
    grant =
      CapabilityGrant.new!(%{
        grant_id: "cap-core-rule-stub-actuator-fan-command-actuator-room-placeholder",
        subject: "core_rule_stub",
        target: "actuator:fan",
        action: "command_actuator",
        scope: "room:placeholder",
        issued_at: "2026-05-10T00:00:00.000Z"
      })

    CapabilityChecker.configure(%{
      {"core_rule_stub", "actuator:fan", "command_actuator", "room:placeholder"} =>
        {:invalid, grant}
    })

    assert {:ok, check} = CapabilityChecker.check(reasoner(), snapshot())
    assert check.result == "deny_invalid_capability"
  end

  defp reasoner do
    ReasonerOutcome.new!(%{
      reasoner_outcome_id: "reasoner-1",
      reasoner_id: "core_rule_stub",
      reasoner_version: "v1",
      snapshot_id: "snap-1",
      snapshot_hash: String.duplicate("a", 64),
      outcome_type: "propose_action",
      target: "actuator:fan",
      requested_state: "on",
      reason: "threshold exceeded",
      confidence_bps: 10000,
      metadata: %{}
    })
  end

  defp snapshot do
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
      source_observation_ids: %{},
      source_observed_at: %{},
      source_received_seq: %{},
      source_received_monotonic_ms: %{},
      source_status: %{
        "co2" => "fresh",
        "humidity" => "fresh",
        "temperature" => "fresh",
        "fan" => "fresh"
      },
      normalized_at: "2026-05-08T12:00:00.000Z",
      freshness: "fresh"
    })
  end
end
