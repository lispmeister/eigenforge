defmodule Eigenforge.Mailbox.LedgerNotifierTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Mailbox.LedgerNotifier

  setup do
    dir =
      Path.join(System.tmp_dir!(), "eigenforge-ledger-notifier-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: Path.join(dir, "ledger.sqlite3"),
         core_node_id: "core_a",
         secret: "notifier-secret",
         name: nil}
    )

    on_exit(fn -> File.rm_rf(dir) end)

    %{writer: writer}
  end

  test "publishes a lightweight notification when an after-action event commits", %{
    writer: writer
  } do
    assert {:ok, _} = LedgerNotifier.subscribe()

    assert {:ok, event} =
             LedgerWriter.append(writer, %{
               event_type: "after_action_recorded",
               consensus_decision_id: "decision-1",
               consensus_status: "single_core_finalized",
               correlation_id: "corr-1",
               subject: "core_rule_stub",
               source_app: "eigenforge_core",
               payload: %{
                 "format_version" => "json-canonical-v1",
                 "schema_id" => "eigenforge.after_action_event",
                 "schema_version" => 1,
                 "after_action_id" => "after-1",
                 "command_id" => "cmd-1",
                 "idempotency_key" => "idem-1",
                 "effect_key" => "effect-1",
                 "target" => "actuator:fan",
                 "requested_state" => "on",
                 "status" => "timed_out",
                 "observed_at" => "2026-05-10T12:00:00.000Z",
                 "reported_at" => "2026-05-10T12:00:00.000Z"
               }
             })

    assert_receive {:mailbox_command, "ledger_events:committed", %{"notification" => notification}}
    assert notification["event_id"] == event.event_id
    assert notification["event_type"] == "after_action_recorded"
    assert notification["core_node_id"] == "core_a"
  end
end
