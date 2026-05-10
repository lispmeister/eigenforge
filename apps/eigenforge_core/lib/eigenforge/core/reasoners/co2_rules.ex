defmodule Eigenforge.Core.Reasoners.Co2Rules do
  @moduledoc """
  Deterministic V1 CO2 threshold reasoner.
  """

  @behaviour Eigenforge.Core.Reasoner

  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.TraceIdentity

  @target "actuator:fan"
  @reasoner_id "core_rule_stub"
  @reasoner_version "v1"

  @impl true
  def reason(%NormalizedSnapshot{freshness: "stale"} = snapshot) do
    outcome(
      snapshot,
      "insufficient_fresh_data",
      nil,
      nil,
      "CO2 reading is stale; deny actuator command."
    )
  end

  def reason(%NormalizedSnapshot{source_status: %{"co2" => status}} = snapshot)
      when status in ["stale", "unknown", "malformed", "missing", "unavailable"] do
    outcome(
      snapshot,
      "insufficient_fresh_data",
      nil,
      nil,
      "CO2 reading is #{status}; deny actuator command."
    )
  end

  def reason(%NormalizedSnapshot{co2_ppm: co2, fan_state: "on"} = snapshot) when co2 > 1000 do
    outcome(
      snapshot,
      "propose_no_action",
      @target,
      "on",
      "Threshold reached but no action due to CO2 fan actuator already in state ON."
    )
  end

  def reason(%NormalizedSnapshot{co2_ppm: co2} = snapshot) when co2 > 1000 do
    outcome(
      snapshot,
      "propose_action",
      @target,
      "on",
      "CO2 #{co2} ppm exceeds 1000 ppm threshold; propose vent fan ON."
    )
  end

  def reason(%NormalizedSnapshot{co2_ppm: co2, fan_state: "off"} = snapshot) when co2 < 500 do
    outcome(
      snapshot,
      "propose_no_action",
      @target,
      "off",
      "Threshold reached but no action due to CO2 fan actuator already in state OFF."
    )
  end

  def reason(%NormalizedSnapshot{co2_ppm: co2} = snapshot) when co2 < 500 do
    outcome(
      snapshot,
      "propose_action",
      @target,
      "off",
      "CO2 #{co2} ppm is below 500 ppm threshold; propose vent fan OFF."
    )
  end

  def reason(snapshot) do
    outcome(
      snapshot,
      "no_threshold_event",
      nil,
      nil,
      "CO2 is inside nominal range; no threshold event."
    )
  end

  defp outcome(snapshot, type, target, requested_state, reason) do
    attrs = %{
      reasoner_outcome_id:
        TraceIdentity.stable_id("reasoner", [snapshot.snapshot_id, type, requested_state || "none"]),
      reasoner_id: @reasoner_id,
      reasoner_version: @reasoner_version,
      snapshot_id: snapshot.snapshot_id,
      snapshot_hash: snapshot.snapshot_hash,
      outcome_type: type,
      target: target,
      requested_state: requested_state,
      reason: reason,
      confidence_bps: 10000,
      metadata: %{}
    }

    {:ok, ReasonerOutcome.new!(attrs)}
  end
end
