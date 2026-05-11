defmodule Eigenforge.Core.AfterActionObserverTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Core.AfterActionObserver

  test "confirms changed when a newer observation reaches the requested state" do
    command = command_envelope(%{requested_state: "on", snapshot_seq: 5})

    assert {:ok, event} =
             AfterActionObserver.interpret_observation(
               command,
               %{"fan_state" => "off"},
               %{
                 observed_state: "on",
                 source_observation_id: "obs-6",
                 source_received_seq: 6,
                 reported_at: "2026-05-10T12:00:03.000Z"
               }
             )

    assert event.status == "confirmed_changed"
    assert event.observed_state == "on"
  end

  test "confirms already in state when pre-command state already matched" do
    command = command_envelope(%{requested_state: "on", snapshot_seq: 5})

    assert {:ok, event} =
             AfterActionObserver.interpret_observation(
               command,
               %{"fan_state" => "on"},
               %{
                 observed_state: "on",
                 source_observation_id: "obs-6",
                 source_received_seq: 6,
                 reported_at: "2026-05-10T12:00:03.000Z"
               }
             )

    assert event.status == "confirmed_already_in_state"
  end

  test "records mismatch when a newer observation contradicts the requested state" do
    command = command_envelope(%{requested_state: "on", snapshot_seq: 5})

    assert {:ok, event} =
             AfterActionObserver.interpret_observation(
               command,
               %{"fan_state" => "off"},
               %{
                 observed_state: "off",
                 source_observation_id: "obs-6",
                 source_received_seq: 6,
                 reported_at: "2026-05-10T12:00:03.000Z"
               }
             )

    assert event.status == "state_mismatch"
  end

  test "rejects confirmation evidence that predates the command receive ordering" do
    command = command_envelope(%{requested_state: "on", snapshot_seq: 5})

    assert {:error, :stale_confirmation_evidence} =
             AfterActionObserver.interpret_observation(
               command,
               %{"fan_state" => "off"},
               %{
                 observed_state: "on",
                 source_observation_id: "obs-4",
                 source_received_seq: 4,
                 reported_at: "2026-05-10T12:00:03.000Z"
               }
             )
  end

  test "maps adapter rejection and timeout to terminal statuses" do
    command = command_envelope(%{requested_state: "off", snapshot_seq: 2})

    assert {:ok, rejected} =
             AfterActionObserver.interpret_fault(command, %{
               fault_type: "adapter_rejected",
               event_id: "fault-3",
               source_received_seq: 3,
               reported_at: "2026-05-10T12:00:03.000Z"
             })

    assert rejected.status == "adapter_rejected"
    assert AfterActionObserver.terminal_status?(rejected.status)

    assert {:ok, timed_out} =
             AfterActionObserver.timeout(command, reported_at: "2026-05-10T12:00:05.000Z")

    assert timed_out.status == "timed_out"
    assert AfterActionObserver.terminal_status?(timed_out.status)
  end

  defp command_envelope(overrides) do
    base = %{
      command_id: "cmd-1",
      idempotency_key: "idem-1",
      effect_key: "effect-1",
      subject: "core_rule_stub",
      target: "actuator:fan",
      action: "command_actuator",
      scope: "room:placeholder",
      requested_state: "on",
      snapshot_id: "snap-1",
      snapshot_seq: 1,
      decision_event_id: "event-4",
      reasoner_outcome_event_id: "event-2",
      capability_event_id: "event-3",
      policy_decision_id: "policy-1",
      issued_at: "2026-05-10T12:00:02.000Z",
      expires_at: "2026-05-10T12:00:07.000Z",
      payload_hash: String.duplicate("c", 64),
      signature_version: "hmac-sha256-v1",
      signature: "sig-cmd"
    }

    base
    |> Map.merge(Map.new(overrides))
    |> CommandEnvelope.new!()
  end
end
