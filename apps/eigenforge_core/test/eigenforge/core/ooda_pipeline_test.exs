defmodule Eigenforge.Core.OodaPipelineTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.PubSub
  alias Eigenforge.Core.SnapshotSubscriber
  alias Eigenforge.Mailbox.CommandPublisher
  alias Eigenforge.Trace

  defmodule PendingAfterActionObserver do
    def observe(_command), do: {:ok, nil}
  end

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-#{System.unique_integer([:positive])}.sqlite3"
      )

    pubsub_registry = Module.concat(__MODULE__, "CoreRegistry#{System.unique_integer([:positive])}")
    mailbox_registry = Module.concat(__MODULE__, "MailboxRegistry#{System.unique_integer([:positive])}")
    subscriber_name = Module.concat(__MODULE__, "Subscriber#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter, db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: nil}
      )

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       name: subscriber_name}
    )

    on_exit(fn ->
      File.rm(db_path)
      File.rm("#{db_path}-wal")
      File.rm("#{db_path}-shm")
    end)

    %{db_path: db_path, pubsub_registry: pubsub_registry, mailbox_registry: mailbox_registry}
  end

  test "published snapshot flows through supervised pipeline and publishes command after ledger append", %{
    db_path: db_path,
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry
  } do
    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: mailbox_registry)

    fixture = %{
      "snapshot_id" => "snap-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("a", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{},
      "source_observed_at" => %{},
      "source_received_seq" => %{},
      "source_received_monotonic_ms" => %{},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok = PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    assert_receive {:mailbox_command, "commands:io", published_command}, 1_000
    assert is_binary(published_command["command_id"])

    assert {:ok, rows} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT event_id, event_type, payload FROM ledger_events ORDER BY sequence ASC;"
             )

    event_types = Enum.map(rows, & &1["event_type"])

    assert event_types == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "capability_check_recorded",
             "policy_decision_recorded",
             "command_envelope_issued",
             "after_action_recorded"
           ]

    assert {:ok, trace} = Trace.run(fixture, "inline-fixture")
    assert Enum.map(trace["ledger_events"], & &1["event_type"]) == Enum.drop(event_types, 1)

    by_type = Map.new(rows, fn row -> {row["event_type"], row} end)
    command_payload = by_type["command_envelope_issued"]["payload"] |> Contracts.decode_json!()

    assert command_payload["decision_event_id"] == by_type["command_envelope_issued"]["event_id"]
    assert command_payload["reasoner_outcome_event_id"] == by_type["reasoner_outcome_recorded"]["event_id"]
    assert command_payload["capability_event_id"] == by_type["capability_check_recorded"]["event_id"]
  end

  test "duplicate snapshot ids are ignored after the first processed delivery", %{
    db_path: db_path,
    pubsub_registry: pubsub_registry
  } do
    fixture = %{
      "snapshot_id" => "snap-dup",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("a", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{},
      "source_observed_at" => %{},
      "source_received_seq" => %{},
      "source_received_monotonic_ms" => %{},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok = PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)
    assert :ok = PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    event_types = wait_for_event_types(db_path)

    assert event_types == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "capability_check_recorded",
             "policy_decision_recorded",
             "command_envelope_issued",
             "after_action_recorded"
           ]
  end

  test "suppresses equivalent in-flight effect commands across snapshot ids" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-inflight-#{System.unique_integer([:positive])}.sqlite3"
      )

    pubsub_registry = Module.concat(__MODULE__, "InflightCoreRegistry#{System.unique_integer([:positive])}")
    mailbox_registry = Module.concat(__MODULE__, "InflightMailboxRegistry#{System.unique_integer([:positive])}")
    writer_name = Module.concat(__MODULE__, "InflightWriter#{System.unique_integer([:positive])}")
    subscriber_name = Module.concat(__MODULE__, "PendingSubscriber#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       after_action_observer: PendingAfterActionObserver,
       name: subscriber_name}
    )

    on_exit(fn ->
      File.rm(db_path)
      File.rm("#{db_path}-wal")
      File.rm("#{db_path}-shm")
    end)

    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: mailbox_registry)

    snapshot_one = %{
      "snapshot_id" => "snap-effect-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("d", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{},
      "source_received_monotonic_ms" => %{},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    snapshot_two = %{snapshot_one | "snapshot_id" => "snap-effect-2", "snapshot_seq" => 2}

    assert :ok = PubSub.publish("io_state:room:placeholder", snapshot_one, registry_name: pubsub_registry)
    assert_receive {:mailbox_command, "commands:io", _first_command}, 1_000

    assert :ok = PubSub.publish("io_state:room:placeholder", snapshot_two, registry_name: pubsub_registry)
    refute_receive {:mailbox_command, "commands:io", _second_command}, 500
  end

  defp wait_for_event_types(db_path, attempts \\ 20)

  defp wait_for_event_types(db_path, attempts) when attempts > 0 do
    case LedgerSQLite.query_json(db_path, "SELECT event_type FROM ledger_events ORDER BY sequence ASC;") do
      {:ok, rows} ->
        event_types = Enum.map(rows, & &1["event_type"])

        if event_types == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "capability_check_recorded",
             "policy_decision_recorded",
             "command_envelope_issued",
             "after_action_recorded"
           ] do
          event_types
        else
          Process.sleep(50)
          wait_for_event_types(db_path, attempts - 1)
        end

      {:error, _reason} ->
        Process.sleep(50)
        wait_for_event_types(db_path, attempts - 1)
    end
  end

  defp wait_for_event_types(_db_path, 0) do
    flunk("timed out waiting for expected duplicate-suppressed ledger chain")
  end
end
