defmodule Eigenforge.Mailbox.ReceiptStoreTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Mailbox.CommandPublisher
  alias Eigenforge.Mailbox.ReceiptStore

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-mailbox-#{System.unique_integer([:positive])}"
      )

    path = Path.join(dir, "receipts.json")
    registry_name = Module.concat(__MODULE__, "Registry#{System.unique_integer([:positive])}")
    store_name = Module.concat(__MODULE__, "Store#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    start_supervised!({Registry, keys: :duplicate, name: registry_name})

    store =
      start_supervised!(
        {ReceiptStore, path: path, secret: "mailbox-secret", name: store_name}
      )

    on_exit(fn -> File.rm_rf(dir) end)

    %{path: path, registry_name: registry_name, store: store}
  end

  test "stores signed receipts durably and tracks delivery phases", %{
    path: path,
    store: store
  } do
    command = command()

    assert {:ok, receipt} =
             ReceiptStore.store_receipt(store, "commands:io", command,
               ledger_sequence: 5,
               ledger_event_hash: String.duplicate("a", 64),
               decision_event_id: command["decision_event_id"]
             )

    assert Contracts.verify_hmac(receipt, "mailbox-secret", receipt.signature, "eigenforge:v1:delivery_receipt")

    assert :ok =
             ReceiptStore.mark_phase(store, receipt.receipt_id, "publish_attempted", %{
               published_at: receipt.delivered_at
             })

    assert :ok =
             ReceiptStore.mark_phase(store, receipt.receipt_id, "io_accepted", %{
               accepted_at: receipt.delivered_at
             })

    assert {:ok, entry} = ReceiptStore.fetch(store, receipt.receipt_id)
    assert entry["delivery_phase"] == "io_accepted"
    assert is_binary(entry["receipt"]["signature"])
    assert {:ok, [_entry]} = ReceiptStore.entries_for_command(store, command["command_id"])

    persisted =
      path
      |> File.read!()
      |> Contracts.decode_json!()

    assert get_in(persisted, ["receipts", receipt.receipt_id, "receipt", "signature"]) ==
             receipt.signature

    assert Contracts.verify_hmac(
             get_in(persisted, ["receipts", receipt.receipt_id, "receipt"]),
             "mailbox-secret",
             receipt.signature,
             "eigenforge:v1:delivery_receipt"
           )

    assert File.exists?(path)
    assert File.exists?(path <> ".manifest.json")
  end

  test "restart bootstrap rejects tampered persisted receipts", %{path: path, store: store} do
    command = command()

    assert {:ok, receipt} =
             ReceiptStore.store_receipt(store, "commands:io", command,
               ledger_sequence: 5,
               ledger_event_hash: String.duplicate("d", 64),
               decision_event_id: command["decision_event_id"]
             )

    persisted =
      path
      |> File.read!()
      |> Contracts.decode_json!()
      |> put_in(["receipts", receipt.receipt_id, "receipt", "signature"], "tampered-signature")

    File.write!(path, Contracts.canonical_json(persisted) <> "\n")

    tampered_name = Module.concat(__MODULE__, "Tampered#{System.unique_integer([:positive])}")
    restarted = start_supervised!({ReceiptStore, path: path, secret: "mailbox-secret", name: tampered_name})

    assert {:error, :receipt_store_unavailable} =
             ReceiptStore.store_receipt(restarted, "commands:io", command,
               ledger_sequence: 6,
               ledger_event_hash: String.duplicate("e", 64),
               decision_event_id: command["decision_event_id"]
             )
  end

  test "restart bootstrap rejects tampered manifests and does not publish while degraded", %{
    path: path,
    registry_name: registry_name
  } do
    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: registry_name)

    manifest_path = path <> ".manifest.json"

    tampered_manifest =
      manifest_path
      |> File.read!()
      |> Contracts.decode_json!()
      |> Map.put("signature", "tampered")

    File.write!(manifest_path, Contracts.canonical_json(tampered_manifest) <> "\n")

    degraded_name = Module.concat(__MODULE__, "ManifestTampered#{System.unique_integer([:positive])}")
    restarted = start_supervised!({ReceiptStore, path: path, secret: "mailbox-secret", name: degraded_name})

    assert {:error, :receipt_store_unavailable} =
             CommandPublisher.publish("commands:io", command(),
               registry_name: registry_name,
               receipt_store: restarted,
               ledger_sequence: 7,
               ledger_event_hash: String.duplicate("f", 64),
               decision_event_id: "event-4"
             )

    refute_receive {:mailbox_command, "commands:io", _payload}, 300
  end

  test "publisher wraps command and receipt and records publish_attempted", %{
    registry_name: registry_name,
    store: store
  } do
    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: registry_name)

    command = command()

    assert :ok =
             CommandPublisher.publish("commands:io", command,
               registry_name: registry_name,
               receipt_store: store,
               ledger_sequence: 5,
               ledger_event_hash: String.duplicate("b", 64),
               decision_event_id: command["decision_event_id"]
             )

    assert_receive {:mailbox_command, "commands:io", payload}, 1_000
    assert %{"command" => delivered_command, "receipt" => delivered_receipt} = payload
    assert delivered_command["command_id"] == command["command_id"]
    assert delivered_receipt["command_id"] == command["command_id"]

    assert {:ok, entry} = ReceiptStore.fetch(store, delivered_receipt["receipt_id"])
    assert entry["delivery_phase"] == "publish_attempted"
  end

  defp command do
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
      decision_event_id: "event-4",
      reasoner_outcome_event_id: "event-2",
      capability_event_id: "event-3",
      policy_decision_id: "policy-1",
      issued_at: "2026-05-10T12:00:02.000Z",
      expires_at: "2099-05-10T12:00:07.000Z",
      payload_hash: String.duplicate("c", 64),
      signature_version: "hmac-sha256-v1",
      signature:
        Contracts.sign_hmac_excluding(
          %{
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
            expires_at: "2099-05-10T12:00:07.000Z",
            payload_hash: String.duplicate("c", 64),
            signature_version: "hmac-sha256-v1",
            signature: ""
          },
          "mailbox-secret",
          [:signature],
          "eigenforge:v1:command_envelope"
        )
    })
    |> Contracts.signable_map()
  end
end
