defmodule Eigenforge.Mailbox.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Mailbox.Projections
  alias Eigenforge.Mailbox.ReceiptStore

  setup do
    dir =
      Path.join(System.tmp_dir!(), "eigenforge-mailbox-projections-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf(dir) end)

    store_name = Module.concat(__MODULE__, "ReceiptStore#{System.unique_integer([:positive])}")

    store =
      start_supervised!(
        {ReceiptStore,
         path: Path.join(dir, "receipts.json"),
         secret: "projection-secret",
         name: store_name}
      )

    %{store: store}
  end

  test "reports pending commands and delivery status from receipt state", %{store: store} do
    command = %{
      "command_id" => "cmd-1",
      "idempotency_key" => "idem-1",
      "effect_key" => "effect-1",
      "target" => "actuator:fan",
      "requested_state" => "on"
    }

    assert {:ok, receipt} =
             ReceiptStore.store_receipt(store, "commands:io", command,
               ledger_sequence: 1,
               ledger_event_hash: String.duplicate("a", 64),
               decision_event_id: "decision-1"
             )

    assert {:ok, pending} = Projections.pending_commands(store)
    assert length(pending) == 1

    assert {:ok, entry} = Projections.delivery_status(store, receipt.receipt_id)
    assert entry["delivery_phase"] == "receipt_stored"

    assert {:ok, receipts} = Projections.receipts_for_command(store, "cmd-1")
    assert length(receipts) == 1

    assert :ok = ReceiptStore.mark_phase(store, receipt.receipt_id, "io_accepted", %{})
    assert {:ok, []} = Projections.pending_commands(store)
  end

  test "ignores receipts for other commands", %{store: store} do
    command = %{
      "command_id" => "cmd-2",
      "idempotency_key" => "idem-2",
      "effect_key" => "effect-2",
      "target" => "actuator:fan",
      "requested_state" => "off"
    }

    assert {:ok, receipt} =
             ReceiptStore.store_receipt(store, "commands:io", command,
               ledger_sequence: 1,
               ledger_event_hash: String.duplicate("b", 64),
               decision_event_id: "decision-2"
             )

    assert {:ok, []} = Projections.receipts_for_command(store, "missing-cmd")
    assert {:ok, [%{"receipt" => %{"command_id" => "cmd-2"}}]} = Projections.pending_commands(store)

    assert {:ok, receipts} = Projections.receipts_for_command(store, "cmd-2")
    assert Enum.map(receipts, &get_in(&1, ["receipt", "command_id"])) == ["cmd-2"]

    assert {:ok, entry} = Projections.delivery_status(store, receipt.receipt_id)
    assert entry["receipt"]["command_id"] == "cmd-2"
  end
end
