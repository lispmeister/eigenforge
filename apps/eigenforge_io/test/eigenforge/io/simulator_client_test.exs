defmodule Eigenforge.IO.SimulatorClientTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.IoFaultStatus
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.SnapshotSubscriber
  alias Eigenforge.Mailbox.CommandPublisher
  alias Eigenforge.IO.SimulatorClient

  setup do
    dir = Path.join(System.tmp_dir!(), "eigenforge-io-sim-#{System.unique_integer([:positive])}")
    db_path = Path.join(dir, "core.sqlite3")
    log_path = Path.join(dir, "io_fault_status.log")
    fixtures_dir = Path.expand("../../../../../config/simulator_snapshots", __DIR__)
    pubsub_registry = Module.concat(__MODULE__, "CoreRegistry#{System.unique_integer([:positive])}")
    mailbox_registry = Module.concat(__MODULE__, "MailboxRegistry#{System.unique_integer([:positive])}")
    fault_registry = Module.concat(__MODULE__, "FaultRegistry#{System.unique_integer([:positive])}")
    subscriber_name = Module.concat(__MODULE__, "Subscriber#{System.unique_integer([:positive])}")
    io_fault_status_name = Module.concat(__MODULE__, "IoFaultStatus#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})
    start_supervised!({Registry, keys: :duplicate, name: fault_registry})

    writer =
      start_supervised!(
        {LedgerWriter, db_path: db_path, core_node_id: "core_a", secret: "sim-secret", name: nil}
      )

    io_fault_status =
      start_supervised!(
        {IoFaultStatus,
         log_path: log_path,
         hmac_secret: "sim-secret",
         default_room_id: "placeholder",
         writer: writer,
         registry_name: fault_registry,
         name: io_fault_status_name}
      )

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       writer: writer,
       secret: "sim-secret",
       name: subscriber_name}
    )

    on_exit(fn -> File.rm_rf(dir) end)

    %{
      db_path: db_path,
      fixtures_dir: fixtures_dir,
      pubsub_registry: pubsub_registry,
      mailbox_registry: mailbox_registry,
      io_fault_status: io_fault_status
    }
  end

  test "publishes simulator snapshots through the core pipeline and emits malformed observation faults", %{
    db_path: db_path,
    fixtures_dir: fixtures_dir,
    mailbox_registry: mailbox_registry,
    io_fault_status: io_fault_status,
    pubsub_registry: pubsub_registry
  } do
    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: mailbox_registry)

    {:ok, _client} =
      start_supervised(
        {SimulatorClient,
      fixtures_dir: fixtures_dir,
      io_fault_status: io_fault_status,
      pubsub_registry: pubsub_registry,
      name: Module.concat(__MODULE__, "Client#{System.unique_integer([:positive])}")}
      )

    assert_receive {:mailbox_command, "commands:io", high_on_command}, 1_000
    assert high_on_command["requested_state"] == "on"

    assert_receive {:mailbox_command, "commands:io", low_off_command}, 1_000
    assert low_off_command["requested_state"] == "off"

    event_types =
      wait_for_event_types(db_path, fn event_types ->
        Enum.member?(event_types, "stale_snapshot_denied") and
          Enum.member?(event_types, "io_fault_observed")
      end)

    assert Enum.count(event_types, &(&1 == "command_envelope_issued")) >= 2
    assert Enum.member?(event_types, "stale_snapshot_denied")
    assert Enum.member?(event_types, "io_fault_observed")
  end

  defp wait_for_event_types(db_path, predicate, attempts \\ 20)

  defp wait_for_event_types(db_path, predicate, attempts) when attempts > 0 do
    case LedgerSQLite.query_json(db_path, "SELECT event_type FROM ledger_events ORDER BY sequence ASC;") do
      {:ok, rows} ->
        event_types = Enum.map(rows, & &1["event_type"])

        if predicate.(event_types) do
          event_types
        else
          Process.sleep(50)
          wait_for_event_types(db_path, predicate, attempts - 1)
        end

      {:error, {:sqlite_query_failed, message}} when is_binary(message) ->
        Process.sleep(50)
        wait_for_event_types(db_path, predicate, attempts - 1)
    end
  end

  defp wait_for_event_types(_db_path, _predicate, 0) do
    flunk("timed out waiting for expected simulator ledger events")
  end
end
