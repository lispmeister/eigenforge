defmodule Eigenforge.Trace do
  @moduledoc """
  Deterministic simulator-backed trace runner for the V1 vertical slice.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.AfterActionEvent
  alias Eigenforge.Contracts.CapabilityCheck
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Contracts.DeliveryReceipt
  alias Eigenforge.Contracts.LedgerEvent
  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Contracts.PolicyDecision
  alias Eigenforge.Contracts.ReasonerOutcome

  @secret "eigenforge-v1-test-secret"
  @subject "core_rule_stub"
  @target "actuator:fan"
  @action "command_actuator"
  @scope "room:placeholder"
  @grant_id "cap-core-rule-stub-fan"
  @reasoner_id "core_rule_stub"
  @reasoner_version "v1"
  @signature_version "hmac-sha256-v1"
  @genesis_previous_hash "eigenforge-ledger-genesis-v1"

  @type run_result :: {:ok, map()} | {:error, term()}

  @doc """
  Runs a deterministic trace from a normalized snapshot fixture path.
  """
  @spec run_file(Path.t()) :: run_result()
  def run_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, fixture} <- decode(body),
         {:ok, trace} <- run(fixture, path) do
      {:ok, trace}
    end
  end

  @doc """
  Runs a deterministic trace from a fixture map.
  """
  @spec run(map(), Path.t() | nil) :: run_result()
  def run(fixture, fixture_path \\ nil) when is_map(fixture) do
    with {:ok, snapshot} <- build_snapshot(fixture),
         {:ok, reasoner} <- reason(snapshot),
         {:ok, capability} <- capability(reasoner, snapshot),
         {:ok, policy} <- policy(reasoner, capability, snapshot) do
      command = maybe_command(reasoner, capability, policy, snapshot)
      after_action = maybe_after_action(command)

      payloads =
        [reasoner, capability, policy, command, after_action]
        |> Enum.reject(&is_nil/1)

      ledger_events = build_ledger(payloads, snapshot)
      delivery = maybe_delivery(command, ledger_events)

      trace =
        %{
          "trace_id" => stable_id("trace", [snapshot.snapshot_id]),
          "fixture" => fixture_path,
          "steps" => steps(reasoner, capability, policy, command, delivery, after_action),
          "ledger_events" => Enum.map(ledger_events, &public_map/1),
          "command_envelopes" => maybe_list(command),
          "delivery_receipts" => maybe_list(delivery),
          "after_actions" => maybe_list(after_action),
          "verification" => verify_trace(ledger_events, command, delivery, after_action)
        }

      {:ok, trace}
    end
  end

  @doc """
  Verifies a trace JSON file produced by `run_file/1`.
  """
  @spec verify_file(Path.t()) :: :ok | {:error, term()}
  def verify_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, trace} <- decode(body) do
      verify_trace_shape(trace)
    end
  end

  defp build_snapshot(fixture) do
    attrs =
      fixture
      |> Map.put_new("snapshot_hash", "")
      |> Map.put_new("humidity_percent", 4500)
      |> Map.put_new("temperature_c", 22000)
      |> Map.put_new("source_entity_ids", %{})
      |> Map.put_new("source_observed_at", %{})
      |> Map.put_new("source_status", %{})
      |> Map.put_new("normalized_at", "2026-05-08T12:00:00.000Z")
      |> Map.put_new("freshness", "fresh")

    snapshot_hash =
      attrs
      |> Map.put("snapshot_hash", nil)
      |> Contracts.hash_canonical()

    attrs
    |> Map.put("snapshot_hash", snapshot_hash)
    |> then(&{:ok, NormalizedSnapshot.new!(&1)})
  rescue
    error -> {:error, {:invalid_snapshot, Exception.message(error)}}
  end

  defp reason(%NormalizedSnapshot{freshness: "stale"} = snapshot) do
    outcome(snapshot, "insufficient_fresh_data", nil, nil, "CO2 reading is stale; deny actuator command.")
  end

  defp reason(%NormalizedSnapshot{source_status: %{"co2" => status}} = snapshot)
       when status in ["stale", "unknown", "malformed", "missing", "unavailable"] do
    outcome(snapshot, "insufficient_fresh_data", nil, nil, "CO2 reading is #{status}; deny actuator command.")
  end

  defp reason(%NormalizedSnapshot{co2_ppm: co2, fan_state: "on"} = snapshot) when co2 > 1000 do
    outcome(
      snapshot,
      "propose_no_action",
      @target,
      "on",
      "Threshold reached but no action due to CO2 fan actuator already in state ON."
    )
  end

  defp reason(%NormalizedSnapshot{co2_ppm: co2} = snapshot) when co2 > 1000 do
    outcome(snapshot, "propose_action", @target, "on", "CO2 #{co2} ppm exceeds 1000 ppm threshold; propose vent fan ON.")
  end

  defp reason(%NormalizedSnapshot{co2_ppm: co2, fan_state: "off"} = snapshot) when co2 < 500 do
    outcome(
      snapshot,
      "propose_no_action",
      @target,
      "off",
      "Threshold reached but no action due to CO2 fan actuator already in state OFF."
    )
  end

  defp reason(%NormalizedSnapshot{co2_ppm: co2} = snapshot) when co2 < 500 do
    outcome(snapshot, "propose_action", @target, "off", "CO2 #{co2} ppm is below 500 ppm threshold; propose vent fan OFF.")
  end

  defp reason(snapshot) do
    outcome(snapshot, "no_threshold_event", nil, nil, "CO2 is inside nominal range; no threshold event.")
  end

  defp outcome(snapshot, type, target, requested_state, reason) do
    attrs = %{
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

  defp capability(%ReasonerOutcome{outcome_type: "propose_action"} = reasoner, _snapshot) do
    {:ok,
     CapabilityCheck.new!(%{
       capability_check_id: stable_id("cap-check", [reasoner.snapshot_id, reasoner.requested_state]),
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

  defp capability(reasoner, _snapshot) do
    {:ok,
     CapabilityCheck.new!(%{
       capability_check_id: stable_id("cap-check", [reasoner.snapshot_id, reasoner.outcome_type]),
       subject: @subject,
       target: reasoner.target || @target,
       action: @action,
       scope: @scope,
       grant_id: nil,
       result: "allow",
       reason: "No physical command requested.",
       checked_at: timestamp()
     })}
  end

  defp policy(%ReasonerOutcome{outcome_type: "insufficient_fresh_data"} = reasoner, capability, snapshot) do
    policy_decision(reasoner, capability, snapshot, "deny_stale_snapshot", "CO2 input is not fresh enough for actuation.")
  end

  defp policy(%ReasonerOutcome{outcome_type: "propose_action"} = reasoner, capability, snapshot) do
    policy_decision(reasoner, capability, snapshot, "allow", "Capability and policy allow idempotent fan command.")
  end

  defp policy(reasoner, capability, snapshot) do
    policy_decision(reasoner, capability, snapshot, "allow", "No physical execution requested.")
  end

  defp policy_decision(reasoner, capability, snapshot, decision, reason) do
    {:ok,
     PolicyDecision.new!(%{
       policy_decision_id: stable_id("policy", [snapshot.snapshot_id, reasoner.outcome_type, decision]),
       snapshot_id: snapshot.snapshot_id,
       snapshot_hash: snapshot.snapshot_hash,
       reasoner_outcome_id: stable_id("reasoner", [snapshot.snapshot_id, reasoner.outcome_type, reasoner.requested_state || "none"]),
       subject: @subject,
       target: reasoner.target || @target,
       action: @action,
       scope: @scope,
       requested_state: reasoner.requested_state,
       decision: decision,
       capability_grant_id: capability.grant_id,
       capability_status: capability.result,
       reason: reason,
       decided_at: timestamp(),
       metadata: %{}
     })}
  end

  defp maybe_command(%ReasonerOutcome{outcome_type: "propose_action"} = reasoner, _capability, %PolicyDecision{decision: "allow"} = policy, snapshot) do
    base = %{
      command_id: stable_id("cmd", [snapshot.snapshot_id, reasoner.requested_state]),
      idempotency_key: stable_id("idem", [snapshot.room_id, @target, reasoner.requested_state, snapshot.snapshot_id]),
      subject: @subject,
      target: @target,
      action: @action,
      scope: @scope,
      requested_state: reasoner.requested_state,
      snapshot_id: snapshot.snapshot_id,
      snapshot_seq: snapshot.snapshot_seq,
      decision_event_id: stable_id("event", ["command_envelope_issued", snapshot.snapshot_id]),
      reasoner_outcome_event_id: stable_id("event", ["reasoner_outcome_recorded", snapshot.snapshot_id]),
      capability_event_id: stable_id("event", ["capability_check_recorded", snapshot.snapshot_id]),
      policy_decision_id: policy.policy_decision_id,
      issued_at: timestamp(),
      expires_at: "2026-05-08T12:00:05.000Z",
      payload_hash: "",
      signature_version: @signature_version,
      signature: ""
    }

    payload_hash = Contracts.hash_excluding(base, [:payload_hash, :signature])
    unsigned = %{base | payload_hash: payload_hash}
    signature = Contracts.sign_hmac_excluding(unsigned, @secret, [:signature])

    CommandEnvelope.new!(%{unsigned | signature: signature})
  end

  defp maybe_command(_reasoner, _capability, _policy, _snapshot), do: nil

  defp maybe_delivery(nil, _ledger_events), do: nil

  defp maybe_delivery(%CommandEnvelope{} = command, ledger_events) do
    command_event = Enum.find(ledger_events, &(&1.event_type == "command_envelope_issued"))

    base = %{
      receipt_id: stable_id("receipt", [command.command_id]),
      command_id: command.command_id,
      decision_event_id: command.decision_event_id,
      ledger_sequence: command_event.sequence,
      ledger_event_hash: command_event.event_hash,
      delivered_topic: "commands:io",
      delivered_at: timestamp(),
      signature_version: @signature_version,
      signature: ""
    }

    signature = Contracts.sign_hmac_excluding(base, @secret, [:signature])
    DeliveryReceipt.new!(%{base | signature: signature})
  end

  defp maybe_after_action(nil), do: nil

  defp maybe_after_action(%CommandEnvelope{} = command) do
    AfterActionEvent.new!(%{
      after_action_id: stable_id("after-action", [command.command_id]),
      command_id: command.command_id,
      idempotency_key: command.idempotency_key,
      adapter_attempt_id: stable_id("adapter-attempt", [command.command_id]),
      target: command.target,
      requested_state: command.requested_state,
      observed_state: command.requested_state,
      status: "confirmed_changed",
      observed_at: timestamp(),
      reported_at: timestamp(),
      source_observation_ids: [stable_id("sim-observation", [command.command_id])],
      source_fault_event_ids: []
    })
  end

  defp build_ledger(payloads, snapshot) do
    Enum.reduce(payloads, {[], @genesis_previous_hash, 1}, fn payload, {events, previous_hash, sequence} ->
      event_type = event_type(payload)
      event_id = stable_id("event", [event_type, snapshot.snapshot_id])

      base = %{
        event_id: event_id,
        sequence: sequence,
        event_type: event_type,
        causation_id: List.last(events) && List.last(events).event_id,
        correlation_id: stable_id("correlation", [snapshot.snapshot_id]),
        subject: @subject,
        source_app: "eigenforge_core",
        occurred_at: timestamp(),
        observed_at: timestamp(),
        persisted_at: timestamp(),
        payload: Map.from_struct(payload),
        payload_hash: Contracts.hash_canonical(Map.from_struct(payload)),
        previous_event_hash: previous_hash,
        event_hash: "",
        signature_version: @signature_version,
        signature: ""
      }

      event_hash = Contracts.hash_excluding(base, [:event_hash, :signature])
      unsigned = %{base | event_hash: event_hash}
      signature = Contracts.sign_hmac_excluding(unsigned, @secret, [:signature])
      event = LedgerEvent.new!(%{unsigned | signature: signature})

      {events ++ [event], event.event_hash, sequence + 1}
    end)
    |> elem(0)
  end

  defp event_type(%ReasonerOutcome{}), do: "reasoner_outcome_recorded"
  defp event_type(%CapabilityCheck{}), do: "capability_check_recorded"
  defp event_type(%PolicyDecision{decision: "deny_stale_snapshot"}), do: "stale_snapshot_denied"
  defp event_type(%PolicyDecision{}), do: "policy_decision_recorded"
  defp event_type(%CommandEnvelope{}), do: "command_envelope_issued"
  defp event_type(%AfterActionEvent{}), do: "after_action_recorded"

  defp verify_trace(ledger_events, command, delivery, after_action) do
    %{
      "ledger_hash_chain_valid" => ledger_hash_chain_valid?(ledger_events),
      "command_delivery_after_ledger_commit" => is_nil(command) or Enum.any?(ledger_events, &(&1.event_type == "command_envelope_issued")),
      "delivery_receipt_valid" => is_nil(delivery) or (not is_nil(command) and delivery.command_id == command.command_id),
      "after_action_core_authored" => is_nil(after_action) or Enum.any?(ledger_events, &(&1.event_type == "after_action_recorded"))
    }
  end

  defp verify_trace_shape(%{"verification" => verification}) do
    if Enum.all?(verification, fn {_key, value} -> value == true end), do: :ok, else: {:error, {:verification_failed, verification}}
  end

  defp verify_trace_shape(_trace), do: {:error, :missing_verification}

  defp ledger_hash_chain_valid?([]), do: true

  defp ledger_hash_chain_valid?(events) do
    events
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] -> right.previous_event_hash == left.event_hash end)
  end

  defp steps(reasoner, capability, policy, command, delivery, after_action) do
    [
      %{"name" => "reasoner_outcome", "result" => reasoner.outcome_type},
      %{"name" => "capability_check", "result" => capability.result},
      %{"name" => "policy_decision", "result" => policy.decision},
      %{"name" => "command_envelope", "result" => if(command, do: "issued", else: "not_delivered")},
      %{"name" => "delivery_receipt", "result" => if(delivery, do: "issued", else: "not_applicable")},
      %{"name" => "after_action", "result" => if(after_action, do: after_action.status, else: "not_applicable")}
    ]
  end

  defp maybe_list(nil), do: []
  defp maybe_list(%_module{} = struct), do: [public_map(struct)]

  defp public_map(%_module{} = struct), do: struct |> Map.from_struct() |> public_map()

  defp public_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), public_map(value)} end)
  end

  defp public_map(list) when is_list(list), do: Enum.map(list, &public_map/1)
  defp public_map(value), do: value

  defp stable_id(prefix, parts) do
    hash =
      parts
      |> Enum.join(":")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "#{prefix}-#{hash}"
  end

  defp timestamp, do: "2026-05-08T12:00:00.000Z"

  defp decode(body) do
    {:ok, JSON.decode!(body)}
  rescue
    error -> {:error, {:invalid_json, Exception.message(error)}}
  end
end
