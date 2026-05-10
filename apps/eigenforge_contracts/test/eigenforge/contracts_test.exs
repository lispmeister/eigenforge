defmodule Eigenforge.ContractsTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CapabilityGrant
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Contracts.DeliveryReceipt
  alias Eigenforge.Contracts.DeviceInventory
  alias Eigenforge.Contracts.ReasonerOutcome

  test "canonical json sorts keys and preserves forward slashes" do
    assert Contracts.canonical_json(%{"b" => 1, "a" => "https://example.com/a/b"}) ==
             ~s({"a":"https://example.com/a/b","b":1})
  end

  test "decode_json rejects duplicate keys" do
    assert {:error, {:duplicate_key, "a"}} = Contracts.decode_json(~s({"a":1,"a":2}))
  end

  test "signatures use purpose labels and reject the wrong purpose" do
    envelope = command_envelope()
    signature = Contracts.sign_hmac(envelope, "test-secret")

    assert Contracts.verify_hmac(envelope, "test-secret", signature)

    refute Contracts.verify_hmac(
             envelope,
             "test-secret",
             signature,
             "eigenforge:v1:delivery_receipt"
           )
  end

  test "delivery receipt signatures do not require a payload hash field" do
    receipt =
      DeliveryReceipt.new!(%{
        receipt_id: "receipt-1",
        command_id: "cmd-1",
        decision_event_id: "event-1",
        ledger_sequence: 4,
        ledger_event_hash: String.duplicate("a", 64),
        delivered_topic: "commands:io",
        delivered_at: "2026-05-08T12:00:00.000Z",
        signature_version: "hmac-sha256-v1",
        signature: "placeholder"
      })

    signature = Contracts.sign_hmac(receipt, "test-secret")

    assert Contracts.verify_hmac(receipt, "test-secret", signature)
    refute Map.has_key?(Contracts.signable_map(receipt), "payload_hash")
  end

  test "canonical signing rejects floats" do
    assert_raise ArgumentError, ~r/floats are not allowed/, fn ->
      Contracts.sign_hmac(%{"schema_id" => "eigenforge.command_envelope", "value" => 12.5}, "secret")
    end
  end

  test "canonical signing rejects integers outside signed 64-bit range" do
    assert_raise ArgumentError, ~r/signed 64-bit range/, fn ->
      Contracts.sign_hmac(
        %{"schema_id" => "eigenforge.command_envelope", "value" => 9_223_372_036_854_775_808},
        "secret"
      )
    end
  end

  test "canonical signing rejects noncanonical timestamps" do
    assert_raise ArgumentError, ~r/noncanonical V1 timestamp/, fn ->
      Contracts.sign_hmac(
        %{
          "schema_id" => "eigenforge.command_envelope",
          "issued_at" => "2026-05-08T12:00:00Z"
        },
        "secret"
      )
    end
  end

  test "unknown string keys do not create atoms or crash normalization" do
    assert {:error, errors} =
             Contracts.new(CommandEnvelope, %{
               "command_id" => "cmd-1",
               "idempotency_key" => "idem-1",
               "effect_key" => "effect-1",
               "subject" => "core_rule_stub",
               "target" => "actuator:fan",
               "action" => "command_actuator",
               "scope" => "room:placeholder",
               "requested_state" => "on",
               "snapshot_id" => "snap-1",
               "snapshot_seq" => 1,
               "decision_event_id" => "event-3",
               "reasoner_outcome_event_id" => "event-1",
               "capability_event_id" => "event-2",
               "policy_decision_id" => "policy-1",
               "issued_at" => "2026-05-08T12:00:00.000Z",
               "expires_at" => "2026-05-08T12:00:05.000Z",
               "payload_hash" => String.duplicate("b", 64),
               "signature_version" => "hmac-sha256-v1",
               "signature" => "placeholder",
               "future_field" => "ignored"
             })

    assert Enum.any?(errors, fn
             {:schema_error, {:unexpected_property, "$", "future_field"}} -> true
             _other -> false
           end)
  end

  test "schema validation rejects unsupported schema versions" do
    assert_raise ArgumentError, ~r/schema_error/, fn ->
      CapabilityGrant.new!(%{
        schema_version: 2,
        grant_id: "cap-1",
        subject: "core_rule_stub",
        target: "actuator:fan",
        action: "command_actuator",
        scope: "room:placeholder",
        issued_at: "2026-05-08T12:00:00.000Z"
      })
    end
  end

  test "schema validation rejects invalid enum values" do
    assert_raise ArgumentError, ~r/schema_error/, fn ->
      ReasonerOutcome.new!(%{
        reasoner_outcome_id: "outcome-1",
        reasoner_id: "co2_reasoner",
        reasoner_version: "1.0.0",
        snapshot_id: "snap-1",
        snapshot_hash: String.duplicate("a", 64),
        outcome_type: "unexpected_mode",
        reason: "testing invalid enum handling",
        confidence_bps: 8_500,
        metadata: %{},
        target: "actuator:fan",
        requested_state: "on",
        schema_version: 1,
        format_version: "json-canonical-v1",
        schema_id: "eigenforge.reasoner_outcome"
      })
    end
  end

  test "schema validation rejects unexpected nested properties when additionalProperties is false" do
    assert_raise ArgumentError, ~r/schema_error/, fn ->
      DeviceInventory.new!(%{
        extra: "nope",
        rooms: [
          %{
            room_id: "placeholder",
            active: true,
            sensors: [],
            actuators: []
          }
        ]
      })
    end
  end

  defp command_envelope do
    CommandEnvelope.new!(%{
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
      decision_event_id: "event-3",
      reasoner_outcome_event_id: "event-1",
      capability_event_id: "event-2",
      policy_decision_id: "policy-1",
      issued_at: "2026-05-08T12:00:00.000Z",
      expires_at: "2026-05-08T12:00:05.000Z",
      payload_hash: String.duplicate("b", 64),
      signature_version: "hmac-sha256-v1",
      signature: "placeholder"
    })
  end
end
