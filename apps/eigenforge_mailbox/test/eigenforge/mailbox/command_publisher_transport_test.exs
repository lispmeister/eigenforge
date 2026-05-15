defmodule Eigenforge.Mailbox.CommandPublisherTransportTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Mailbox.CommandPublisher
  alias Eigenforge.Mailbox.ReceiptStore

  defmodule SubstituteTransport do
    @behaviour Eigenforge.Mailbox.CommandTransport

    @impl true
    def publish_command(envelope, receipt, opts) do
      send(self(), {:transport_called, envelope, receipt, opts})
      {:ok, %{published: true}}
    end
  end

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-mailbox-transport-#{System.unique_integer([:positive])}"
      )

    path = Path.join(dir, "receipts.json")
    registry_name = Module.concat(__MODULE__, "Registry#{System.unique_integer([:positive])}")
    store_name = Module.concat(__MODULE__, "Store#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    start_supervised!({Registry, keys: :duplicate, name: registry_name})

    store =
      start_supervised!({ReceiptStore, path: path, secret: "mailbox-secret", name: store_name})

    on_exit(fn -> File.rm_rf(dir) end)

    %{registry_name: registry_name, store: store}
  end

  test "publish delegates to the injected transport", %{
    registry_name: registry_name,
    store: store
  } do
    command = command()

    assert :ok =
             CommandPublisher.publish("commands:io", command,
               registry_name: registry_name,
               receipt_store: store,
               ledger_sequence: 5,
               ledger_event_hash: String.duplicate("a", 64),
               decision_event_id: command["decision_event_id"],
               transport: SubstituteTransport
             )

    assert_receive {:transport_called, envelope, receipt, opts}
    assert envelope["command_id"] == command["command_id"]
    assert receipt["command_id"] == command["command_id"]
    assert opts[:registry_name] == registry_name
    assert opts[:topic] == "commands:io"

    assert {:ok, entry} = ReceiptStore.fetch(store, receipt["receipt_id"])
    assert entry["delivery_phase"] == "publish_attempted"
  end

  defp command do
    base =
      CommandEnvelope.new!(%{
        command_id: "cmd-transport",
        idempotency_key: "idem-transport",
        effect_key: "effect-transport",
        subject: "core_rule_stub",
        target: "actuator:fan",
        action: "command_actuator",
        scope: "room:placeholder",
        requested_state: "on",
        snapshot_id: "snap-transport",
        snapshot_seq: 1,
        decision_event_id: "event-transport",
        reasoner_outcome_event_id: "event-2",
        capability_event_id: "event-3",
        policy_decision_id: "policy-transport",
        issued_at: "2026-05-10T12:00:02.000Z",
        expires_at: "2099-05-10T12:00:07.000Z",
        payload_hash: String.duplicate("c", 64),
        signature_version: "hmac-sha256-v1",
        signature: ""
      })

    %{
      base
      | signature: Contracts.sign_hmac(base, "mailbox-secret", "eigenforge:v1:command_envelope")
    }
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end
end
