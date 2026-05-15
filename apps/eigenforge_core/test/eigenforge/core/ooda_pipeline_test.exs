defmodule Eigenforge.Core.OodaPipelineTest do
  use ExUnit.Case, async: false

  alias Eigenforge.Contracts
  alias Eigenforge.Core.IoFaultStatus
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.PubSub
  alias Eigenforge.Core.SnapshotSubscriber
  alias Eigenforge.Mailbox.CommandPublisher
  alias Eigenforge.Mailbox.ReceiptStore
  alias Eigenforge.Trace

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "CoreRegistry#{System.unique_integer([:positive])}")

    fault_registry =
      Module.concat(__MODULE__, "FaultRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(__MODULE__, "MailboxRegistry#{System.unique_integer([:positive])}")

    receipt_store_name =
      Module.concat(__MODULE__, "ReceiptStore#{System.unique_integer([:positive])}")

    subscriber_name = Module.concat(__MODULE__, "Subscriber#{System.unique_integer([:positive])}")
    fault_subscriber_name =
      Module.concat(__MODULE__, "FaultSubscriber#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: fault_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: nil}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    fault_subscriber =
      start_supervised!(
        {Eigenforge.Core.FaultStatusSubscriber,
         room_id: "placeholder",
         db_path: db_path,
         writer: writer,
         mailbox_receipt_store: receipt_store,
         after_action_observer: Eigenforge.Core.AfterActionObserver,
         io_fault_status_registry: fault_registry,
         snapshot_subscriber: subscriber_name,
         name: fault_subscriber_name}
      )

    subscriber =
      start_supervised!(
        {SnapshotSubscriber,
         room_id: "placeholder",
         pubsub_registry: pubsub_registry,
         mailbox_registry: mailbox_registry,
         mailbox_receipt_store: receipt_store,
         writer: writer,
         db_path: db_path,
         secret: "pipeline-secret",
         name: subscriber_name}
      )

    on_exit(fn -> cleanup_artifacts(db_path) end)

    %{
      db_path: db_path,
      pubsub_registry: pubsub_registry,
      fault_registry: fault_registry,
      mailbox_registry: mailbox_registry,
      receipt_store: receipt_store,
      writer: writer,
      fault_subscriber: fault_subscriber,
      subscriber: subscriber
    }
  end

  test "published snapshot commits a command first and records after-action only after a later confirming observation",
       %{
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
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    assert_receive {:mailbox_command, "commands:io", delivery}, 1_000
    assert is_binary(delivery["command"]["command_id"])
    assert is_binary(delivery["receipt"]["receipt_id"])

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
             "command_envelope_issued"
           ]

    assert {:ok, trace} = Trace.run(fixture, "inline-fixture")

    assert Enum.take(Enum.map(trace["ledger_events"], & &1["event_type"]), 4) ==
             Enum.drop(event_types, 1)

    by_type = Map.new(rows, fn row -> {row["event_type"], row} end)
    command_payload = by_type["command_envelope_issued"]["payload"] |> Contracts.decode_json!()

    assert command_payload["decision_event_id"] == by_type["command_envelope_issued"]["event_id"]

    assert command_payload["reasoner_outcome_event_id"] ==
             by_type["reasoner_outcome_recorded"]["event_id"]

    assert command_payload["capability_event_id"] ==
             by_type["capability_check_recorded"]["event_id"]

    follow_up =
      Map.merge(fixture, %{
        "snapshot_id" => "snap-2",
        "snapshot_seq" => 2,
        "fan_state" => "on",
        "source_observation_ids" => %{"fan" => "fan-obs-2"},
        "source_received_seq" => %{"fan" => 2},
        "source_received_monotonic_ms" => %{"fan" => 2},
        "normalized_at" => "2026-05-08T12:00:01.000Z"
      })

    assert :ok =
             PubSub.publish("io_state:room:placeholder", follow_up,
               registry_name: pubsub_registry
             )

    final_event_types =
      wait_for_event_types(db_path, fn types ->
        Enum.take(types, 6) == [
          "ledger_genesis",
          "reasoner_outcome_recorded",
          "capability_check_recorded",
          "policy_decision_recorded",
          "command_envelope_issued",
          "after_action_recorded"
        ]
      end)

    assert "after_action_recorded" in final_event_types
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
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    event_types = wait_for_event_types(db_path)

    assert event_types == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "capability_check_recorded",
             "policy_decision_recorded",
             "command_envelope_issued"
           ]
  end

  test "nominal snapshots coalesce until threshold or projection state changes", %{
    db_path: db_path,
    pubsub_registry: pubsub_registry
  } do
    nominal_a = %{
      "snapshot_id" => "snap-coalesce-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("a", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 900,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{"co2" => "fresh"},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    nominal_b = %{nominal_a | "snapshot_id" => "snap-coalesce-2", "snapshot_seq" => 2}

    threshold =
      Map.merge(nominal_a, %{
        "snapshot_id" => "snap-coalesce-3",
        "snapshot_seq" => 3,
        "snapshot_hash" => String.duplicate("b", 64),
        "co2_ppm" => 1_200,
        "fan_state" => "on",
        "source_observation_ids" => %{"fan" => "fan-obs-3"},
        "source_received_seq" => %{"fan" => 3},
        "source_received_monotonic_ms" => %{"fan" => 3}
      })

    nominal_after_threshold =
      Map.merge(nominal_a, %{
        "snapshot_id" => "snap-coalesce-4",
        "snapshot_seq" => 4,
        "snapshot_hash" => String.duplicate("c", 64),
        "source_observation_ids" => %{"fan" => "fan-obs-4"},
        "source_received_seq" => %{"fan" => 4},
        "source_received_monotonic_ms" => %{"fan" => 4}
      })

    nominal_after_threshold_again =
      Map.merge(nominal_a, %{
        "snapshot_id" => "snap-coalesce-5",
        "snapshot_seq" => 5,
        "snapshot_hash" => String.duplicate("d", 64),
        "source_observation_ids" => %{"fan" => "fan-obs-5"},
        "source_received_seq" => %{"fan" => 5},
        "source_received_monotonic_ms" => %{"fan" => 5}
      })

    assert :ok =
             PubSub.publish("io_state:room:placeholder", nominal_a, registry_name: pubsub_registry)

    assert wait_for_event_types(db_path, &(length(&1) == 3)) == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "policy_decision_recorded"
           ]

    assert :ok =
             PubSub.publish("io_state:room:placeholder", nominal_b, registry_name: pubsub_registry)

    assert wait_for_event_types(db_path, &(length(&1) == 3)) == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "policy_decision_recorded"
           ]

    assert :ok =
             PubSub.publish("io_state:room:placeholder", threshold, registry_name: pubsub_registry)

    assert wait_for_event_types(db_path, &(length(&1) == 5)) == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "policy_decision_recorded",
             "reasoner_outcome_recorded",
             "policy_decision_recorded"
           ]

    assert :ok =
             PubSub.publish("io_state:room:placeholder", nominal_after_threshold,
               registry_name: pubsub_registry
             )

    assert wait_for_event_types(db_path, &(length(&1) == 7)) == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "policy_decision_recorded",
             "reasoner_outcome_recorded",
             "policy_decision_recorded",
             "reasoner_outcome_recorded",
             "policy_decision_recorded"
           ]

    assert :ok =
             PubSub.publish("io_state:room:placeholder", nominal_after_threshold_again,
               registry_name: pubsub_registry
             )

    assert wait_for_event_types(db_path, &(length(&1) == 7)) == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "policy_decision_recorded",
             "reasoner_outcome_recorded",
             "policy_decision_recorded",
             "reasoner_outcome_recorded",
             "policy_decision_recorded"
           ]
  end

  test "stale CO2 snapshot emits reasoner_outcome_recorded, policy_decision_recorded, and stale_snapshot_denied as three separate events",
       %{db_path: db_path, pubsub_registry: pubsub_registry} do
    stale_fixture = %{
      "snapshot_id" => "snap-stale-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("b", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "stale"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", stale_fixture,
               registry_name: pubsub_registry
             )

    event_types =
      wait_for_event_types(db_path, fn types ->
        "stale_snapshot_denied" in types
      end)

    assert [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "stale_snapshot_denied"
           ] = Enum.take(event_types, 3)
  end

  test "a transient pipeline failure does not permanently suppress retry of the same snapshot id",
       %{
         db_path: db_path,
         pubsub_registry: pubsub_registry,
         mailbox_registry: mailbox_registry,
         receipt_store: receipt_store,
         writer: writer,
         subscriber: _subscriber
       } do
    :ets.new(:retry_reasoner_attempts, [:named_table, :public, :set])

    on_exit(fn ->
      if :ets.whereis(:retry_reasoner_attempts) != :undefined do
        :ets.delete(:retry_reasoner_attempts)
      end
    end)

    retry_name = Module.concat(__MODULE__, "RetrySubscriber#{System.unique_integer([:positive])}")
    room_id = "retry-room-#{System.unique_integer([:positive])}"

    start_supervised!(
      {SnapshotSubscriber,
       room_id: room_id,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       reasoner_module: Eigenforge.Core.OodaPipelineTest.RetryReasoner,
       name: retry_name}
    )

    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: mailbox_registry)

    fixture = %{
      "snapshot_id" => "snap-retry",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("a", 64),
      "room_id" => room_id,
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:#{room_id}", fixture, registry_name: pubsub_registry)

    refute_receive {:mailbox_command, "commands:io", _first_delivery}, 300

    assert {:ok, rows_after_failure} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT event_type FROM ledger_events ORDER BY sequence ASC;"
             )

    assert rows_after_failure == [%{"event_type" => "ledger_genesis"}]

    assert :ok =
             PubSub.publish("io_state:room:#{room_id}", fixture, registry_name: pubsub_registry)

    assert_receive {:mailbox_command, "commands:io", delivery}, 1_000
    assert delivery["command"]["snapshot_id"] == "snap-retry"

    final_event_types = wait_for_event_types(db_path)

    assert final_event_types == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "capability_check_recorded",
             "policy_decision_recorded",
             "command_envelope_issued"
           ]
  end

  test "suppresses equivalent in-flight effect commands across snapshot ids" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-inflight-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "InflightCoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(__MODULE__, "InflightMailboxRegistry#{System.unique_integer([:positive])}")

    receipt_store_name =
      Module.concat(__MODULE__, "InflightReceiptStore#{System.unique_integer([:positive])}")

    writer_name = Module.concat(__MODULE__, "InflightWriter#{System.unique_integer([:positive])}")

    subscriber_name =
      Module.concat(__MODULE__, "PendingSubscriber#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       name: subscriber_name}
    )

    on_exit(fn -> cleanup_artifacts(db_path) end)

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

    assert :ok =
             PubSub.publish("io_state:room:placeholder", snapshot_one,
               registry_name: pubsub_registry
             )

    assert_receive {:mailbox_command, "commands:io", _first_delivery}, 1_000

    assert :ok =
             PubSub.publish("io_state:room:placeholder", snapshot_two,
               registry_name: pubsub_registry
             )

    refute_receive {:mailbox_command, "commands:io", _second_delivery}, 500
  end

  test "pending commands record a terminal timed_out after-action when no confirming observation arrives" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-timeout-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "TimeoutCoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(__MODULE__, "TimeoutMailboxRegistry#{System.unique_integer([:positive])}")

    receipt_store_name =
      Module.concat(__MODULE__, "TimeoutReceiptStore#{System.unique_integer([:positive])}")

    writer_name = Module.concat(__MODULE__, "TimeoutWriter#{System.unique_integer([:positive])}")

    subscriber_name =
      Module.concat(__MODULE__, "TimeoutSubscriber#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       after_action_timeout_ms: 100,
       name: subscriber_name}
    )

    on_exit(fn -> cleanup_artifacts(db_path) end)

    fixture = %{
      "snapshot_id" => "snap-timeout-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("a", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    payload_json = wait_for_after_action_payload(db_path)
    timeout_event_types = fetch_event_types(db_path)

    assert Enum.take(timeout_event_types, 6) == [
             "ledger_genesis",
             "reasoner_outcome_recorded",
             "capability_check_recorded",
             "policy_decision_recorded",
             "command_envelope_issued",
             "after_action_recorded"
           ]

    assert %{"status" => "timed_out"} = Contracts.decode_json!(payload_json)
  end

  test "restart recovery records timed_out for an io_accepted command whose after-action deadline elapsed while down" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-recovery-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "RecoveryCoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(__MODULE__, "RecoveryMailboxRegistry#{System.unique_integer([:positive])}")

    receipt_store_name =
      Module.concat(__MODULE__, "RecoveryReceiptStore#{System.unique_integer([:positive])}")

    writer_name = Module.concat(__MODULE__, "RecoveryWriter#{System.unique_integer([:positive])}")

    subscriber_name =
      Module.concat(__MODULE__, "RecoverySubscriber#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    subscriber =
      start_supervised!(
        {SnapshotSubscriber,
         room_id: "placeholder",
         pubsub_registry: pubsub_registry,
         mailbox_registry: mailbox_registry,
         mailbox_receipt_store: receipt_store,
         writer: writer,
         db_path: db_path,
         secret: "pipeline-secret",
         after_action_timeout_ms: 100,
         name: subscriber_name}
      )

    on_exit(fn -> cleanup_artifacts(db_path) end)

    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: mailbox_registry)

    fixture = %{
      "snapshot_id" => "snap-recovery-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("f", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    assert_receive {:mailbox_command, "commands:io", delivery}, 1_000

    assert :ok =
             ReceiptStore.mark_phase(
               receipt_store,
               delivery["receipt"]["receipt_id"],
               "io_accepted",
               %{
                 accepted_at: "2026-05-08T12:00:00.000Z"
               }
             )

    Process.exit(subscriber, :normal)
    Process.sleep(50)

    restarted_name =
      Module.concat(__MODULE__, "RecoverySubscriberRestart#{System.unique_integer([:positive])}")

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       after_action_timeout_ms: 100,
       name: restarted_name}
    )

    payload_json = wait_for_after_action_payload(db_path)
    payload = Contracts.decode_json!(payload_json)
    assert payload["command_id"] == delivery["command"]["command_id"]
    assert payload["status"] == "timed_out"
  end

  test "restart recovery honors persisted deadlines after a wall-clock jump" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-recovery-wall-clock-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "RecoveryClockCoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(
        __MODULE__,
        "RecoveryClockMailboxRegistry#{System.unique_integer([:positive])}"
      )

    receipt_store_name =
      Module.concat(__MODULE__, "RecoveryClockReceiptStore#{System.unique_integer([:positive])}")

    writer_name =
      Module.concat(__MODULE__, "RecoveryClockWriter#{System.unique_integer([:positive])}")

    subscriber_name =
      Module.concat(__MODULE__, "RecoveryClockSubscriber#{System.unique_integer([:positive])}")

    restarted_name =
      Module.concat(
        __MODULE__,
        "RecoveryClockSubscriberRestart#{System.unique_integer([:positive])}"
      )

    clock =
      start_supervised!(
        {Agent,
         fn ->
           %{
             utc: ~U[2026-05-08 12:00:00.000Z],
             monotonic: 1_000
           }
         end}
      )

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    subscriber =
      start_supervised!(
        {SnapshotSubscriber,
         room_id: "placeholder",
         pubsub_registry: pubsub_registry,
         mailbox_registry: mailbox_registry,
         mailbox_receipt_store: receipt_store,
         writer: writer,
         db_path: db_path,
         secret: "pipeline-secret",
         utc_now: fn -> Agent.get(clock, & &1.utc) end,
         monotonic_now_ms: fn -> Agent.get(clock, & &1.monotonic) end,
         after_action_timeout_ms: 100,
         name: subscriber_name}
      )

    on_exit(fn -> cleanup_artifacts(db_path) end)

    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: mailbox_registry)

    fixture = %{
      "snapshot_id" => "snap-recovery-clock-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("e", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    assert_receive {:mailbox_command, "commands:io", delivery}, 1_000

    assert :ok =
             ReceiptStore.mark_phase(
               receipt_store,
               delivery["receipt"]["receipt_id"],
               "io_accepted",
               %{
                 accepted_at: "2026-05-08T12:00:00.000Z"
               }
             )

    Process.exit(subscriber, :normal)
    Process.sleep(50)

    Agent.update(clock, fn _ ->
      %{
        utc: ~U[2101-05-10 12:00:00.000Z],
        monotonic: 1_050
      }
    end)

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       utc_now: fn -> Agent.get(clock, & &1.utc) end,
       monotonic_now_ms: fn -> Agent.get(clock, & &1.monotonic) end,
       after_action_timeout_ms: 100,
       name: restarted_name}
    )

    refute_receive {:mailbox_command, "commands:io", _redelivery}, 200

    payload_json = wait_for_after_action_payload(db_path)
    payload = Contracts.decode_json!(payload_json)
    assert payload["command_id"] == delivery["command"]["command_id"]
    assert payload["status"] == "timed_out"
  end

  test "restart recovery times out commands persisted in receipt_stored and publish_attempted phases without redelivery" do
    Enum.each(["receipt_stored", "publish_attempted"], fn phase ->
      assert_restart_recovery_timeout_for_phase(phase)
    end)
  end

  test "live io faults with newer ordering metadata record terminal adapter_failed after-actions" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-fault-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "FaultCoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(__MODULE__, "FaultMailboxRegistry#{System.unique_integer([:positive])}")

    fault_registry =
      Module.concat(__MODULE__, "FaultStatusRegistry#{System.unique_integer([:positive])}")

    receipt_store_name =
      Module.concat(__MODULE__, "FaultReceiptStore#{System.unique_integer([:positive])}")

    writer_name = Module.concat(__MODULE__, "FaultWriter#{System.unique_integer([:positive])}")

    fault_status_name =
      Module.concat(__MODULE__, "FaultStatus#{System.unique_integer([:positive])}")

    subscriber_name =
      Module.concat(__MODULE__, "FaultSubscriber#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})
    start_supervised!({Registry, keys: :duplicate, name: fault_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    fault_status =
      start_supervised!(
        {IoFaultStatus,
         log_path: db_path <> ".io_fault.log",
         hmac_secret: "pipeline-secret",
         default_room_id: "placeholder",
         writer: writer,
         registry_name: fault_registry,
         name: fault_status_name}
      )

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       io_fault_status_registry: fault_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       after_action_timeout_ms: 30_000,
       name: subscriber_name}
    )

    on_exit(fn -> cleanup_artifacts(db_path) end)

    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: mailbox_registry)

    fixture = %{
      "snapshot_id" => "snap-fault-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("f", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    assert_receive {:mailbox_command, "commands:io", delivery}, 1_000

    assert {:ok, _event} =
             IoFaultStatus.record(fault_status, %{
               source: "home_assistant",
               room_id: "placeholder",
               fault_type: "adapter_execution_failed",
               message: "service unavailable",
               audit: true,
               source_received_seq: 2,
               source_received_monotonic_ms: 2,
               metadata: %{
                 "command_id" => delivery["command"]["command_id"],
                 "target" => delivery["command"]["target"]
               }
             })

    payloads = wait_for_after_action_payloads(db_path)

    assert Enum.any?(payloads, fn payload ->
             payload["command_id"] == delivery["command"]["command_id"] and
               payload["status"] in ["adapter_failed", "timed_out"]
           end)
  end

  test "replayed older actuator observations do not confirm pending commands and the command times out" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-replay-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "ReplayCoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(__MODULE__, "ReplayMailboxRegistry#{System.unique_integer([:positive])}")

    receipt_store_name =
      Module.concat(__MODULE__, "ReplayReceiptStore#{System.unique_integer([:positive])}")

    writer_name = Module.concat(__MODULE__, "ReplayWriter#{System.unique_integer([:positive])}")

    subscriber_name =
      Module.concat(__MODULE__, "ReplaySubscriber#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       after_action_timeout_ms: 100,
       name: subscriber_name}
    )

    on_exit(fn -> cleanup_artifacts(db_path) end)

    fixture = %{
      "snapshot_id" => "snap-replay-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("f", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 5},
      "source_received_monotonic_ms" => %{"fan" => 5},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    wait_for_event_types(db_path)

    replay =
      Map.merge(fixture, %{
        "snapshot_id" => "snap-replay-2",
        "fan_state" => "on",
        "source_observation_ids" => %{"fan" => "fan-obs-old"},
        "source_received_seq" => %{"fan" => 4},
        "source_received_monotonic_ms" => %{"fan" => 4},
        "normalized_at" => "2026-05-08T12:00:01.000Z"
      })

    assert :ok =
             PubSub.publish("io_state:room:placeholder", replay, registry_name: pubsub_registry)

    payload_json = wait_for_after_action_payload(db_path)
    payload = Contracts.decode_json!(payload_json)
    assert payload["status"] == "timed_out"
  end

  test "manual later fan observations can record a state mismatch after-action" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-manual-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "ManualCoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(__MODULE__, "ManualMailboxRegistry#{System.unique_integer([:positive])}")

    receipt_store_name =
      Module.concat(__MODULE__, "ManualReceiptStore#{System.unique_integer([:positive])}")

    writer_name = Module.concat(__MODULE__, "ManualWriter#{System.unique_integer([:positive])}")

    subscriber_name =
      Module.concat(__MODULE__, "ManualSubscriber#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       after_action_timeout_ms: 1_000,
       name: subscriber_name}
    )

    on_exit(fn -> cleanup_artifacts(db_path) end)

    fixture = %{
      "snapshot_id" => "snap-manual-1",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("f", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    wait_for_event_types(db_path)

    manual =
      Map.merge(fixture, %{
        "snapshot_id" => "snap-manual-2",
        "snapshot_seq" => 2,
        "fan_state" => "off",
        "source_observation_ids" => %{"fan" => "fan-obs-2"},
        "source_received_seq" => %{"fan" => 2},
        "source_received_monotonic_ms" => %{"fan" => 2},
        "normalized_at" => "2026-05-08T12:00:01.000Z"
      })

    assert :ok =
             PubSub.publish("io_state:room:placeholder", manual, registry_name: pubsub_registry)

    payload_json = wait_for_after_action_payload(db_path)
    payload = Contracts.decode_json!(payload_json)
    assert payload["status"] == "state_mismatch"
  end

  test "restart recovery resolves pending commands across two rooms" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-two-room-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "TwoRoomCoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(__MODULE__, "TwoRoomMailboxRegistry#{System.unique_integer([:positive])}")

    receipt_store_name =
      Module.concat(__MODULE__, "TwoRoomReceiptStore#{System.unique_integer([:positive])}")

    writer_name = Module.concat(__MODULE__, "TwoRoomWriter#{System.unique_integer([:positive])}")

    sub_a_name = Module.concat(__MODULE__, "TwoRoomSubA#{System.unique_integer([:positive])}")
    sub_b_name = Module.concat(__MODULE__, "TwoRoomSubB#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    sub_a =
      start_supervised!(
        {SnapshotSubscriber,
         room_id: "room-a",
         pubsub_registry: pubsub_registry,
         mailbox_registry: mailbox_registry,
         mailbox_receipt_store: receipt_store,
         writer: writer,
         db_path: db_path,
         secret: "pipeline-secret",
         after_action_timeout_ms: 5_000,
         name: sub_a_name}
      )

    sub_b =
      start_supervised!(
        {SnapshotSubscriber,
         room_id: "room-b",
         pubsub_registry: pubsub_registry,
         mailbox_registry: mailbox_registry,
         mailbox_receipt_store: receipt_store,
         writer: writer,
         db_path: db_path,
         secret: "pipeline-secret",
         after_action_timeout_ms: 5_000,
         name: sub_b_name}
      )

    on_exit(fn -> cleanup_artifacts(db_path) end)

    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: mailbox_registry)

    for {room_id, snap_id} <- [{"room-a", "snap-2room-a"}, {"room-b", "snap-2room-b"}] do
      fixture = %{
        "snapshot_id" => snap_id,
        "snapshot_seq" => 1,
        "snapshot_hash" => String.duplicate("c", 64),
        "room_id" => room_id,
        "co2_ppm" => 1200,
        "humidity_basis_points" => 4500,
        "temperature_millicelsius" => 22_000,
        "fan_state" => "off",
        "source_entity_ids" => %{},
        "source_observation_ids" => %{"fan" => "fan-obs-#{room_id}"},
        "source_observed_at" => %{},
        "source_received_seq" => %{"fan" => 1},
        "source_received_monotonic_ms" => %{"fan" => 1},
        "source_status" => %{},
        "normalized_at" => "2026-05-08T12:00:00.000Z",
        "freshness" => "fresh"
      }

      assert :ok =
               PubSub.publish("io_state:room:#{room_id}", fixture, registry_name: pubsub_registry)
    end

    assert_receive {:mailbox_command, "commands:io", _delivery_a}, 1_000
    assert_receive {:mailbox_command, "commands:io", _delivery_b}, 1_000

    Process.exit(sub_a, :normal)
    Process.exit(sub_b, :normal)
    Process.sleep(50)

    restarted_name =
      Module.concat(__MODULE__, "TwoRoomSubRestart#{System.unique_integer([:positive])}")

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "room-a",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       after_action_timeout_ms: 10,
       name: restarted_name}
    )

    after_action_count =
      wait_for_after_action_count(db_path, 2)

    assert after_action_count == 2
  end

  defp wait_for_event_types(db_path, predicate \\ nil, attempts \\ 200)

  defp wait_for_event_types(db_path, predicate, attempts) when attempts > 0 do
    case LedgerSQLite.query_json(
           db_path,
           "SELECT event_type FROM ledger_events ORDER BY sequence ASC;"
         ) do
      {:ok, rows} ->
        event_types = Enum.map(rows, & &1["event_type"])

        expected? =
          if is_function(predicate, 1) do
            predicate.(event_types)
          else
            event_types == [
              "ledger_genesis",
              "reasoner_outcome_recorded",
              "capability_check_recorded",
              "policy_decision_recorded",
              "command_envelope_issued"
            ]
          end

        if expected? do
          event_types
        else
          Process.sleep(50)
          wait_for_event_types(db_path, predicate, attempts - 1)
        end

      {:error, _reason} ->
        Process.sleep(50)
        wait_for_event_types(db_path, predicate, attempts - 1)
    end
  end

  defp wait_for_event_types(_db_path, _predicate, 0) do
    flunk("timed out waiting for expected duplicate-suppressed ledger chain")
  end

  defp wait_for_after_action_count(db_path, expected, attempts \\ 200)

  defp wait_for_after_action_count(db_path, expected, attempts) when attempts > 0 do
    case LedgerSQLite.query_json(
           db_path,
           "SELECT COUNT(*) AS cnt FROM ledger_events WHERE event_type = 'after_action_recorded';"
         ) do
      {:ok, [%{"cnt" => count}]} when count >= expected ->
        count

      _ ->
        Process.sleep(50)
        wait_for_after_action_count(db_path, expected, attempts - 1)
    end
  end

  defp wait_for_after_action_count(_db_path, _expected, 0) do
    flunk("timed out waiting for expected after_action count")
  end

  defp wait_for_after_action_payload(db_path, attempts \\ 200)

  defp wait_for_after_action_payload(db_path, attempts) when attempts > 0 do
    case LedgerSQLite.query_json(
           db_path,
           "SELECT payload FROM ledger_events WHERE event_type = 'after_action_recorded' ORDER BY sequence DESC LIMIT 1;"
         ) do
      {:ok, [%{"payload" => payload_json}]} ->
        payload_json

      _ ->
        Process.sleep(50)
        wait_for_after_action_payload(db_path, attempts - 1)
    end
  end

  defp wait_for_after_action_payload(_db_path, 0) do
    flunk("timed out waiting for durable after_action payload")
  end

  defp wait_for_after_action_payloads(db_path, attempts \\ 200)

  defp wait_for_after_action_payloads(db_path, attempts) when attempts > 0 do
    case LedgerSQLite.query_json(
           db_path,
           "SELECT payload FROM ledger_events WHERE event_type = 'after_action_recorded' ORDER BY sequence ASC;"
         ) do
      {:ok, []} ->
        Process.sleep(50)
        wait_for_after_action_payloads(db_path, attempts - 1)

      {:ok, rows} ->
        Enum.map(rows, fn %{"payload" => payload_json} -> Contracts.decode_json!(payload_json) end)
    end
  end

  defp wait_for_after_action_payloads(_db_path, 0) do
    flunk("timed out waiting for any after_action payloads")
  end

  defp fetch_event_types(db_path) do
    assert {:ok, rows} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT event_type FROM ledger_events ORDER BY sequence ASC;"
             )

    Enum.map(rows, & &1["event_type"])
  end

  defp assert_restart_recovery_timeout_for_phase(phase) do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ooda-recovery-#{phase}-#{System.unique_integer([:positive])}.sqlite3"
      )

    cleanup_artifacts(db_path)

    pubsub_registry =
      Module.concat(__MODULE__, "RecoveryPhaseCoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(
        __MODULE__,
        "RecoveryPhaseMailboxRegistry#{System.unique_integer([:positive])}"
      )

    receipt_store_name =
      Module.concat(__MODULE__, "RecoveryPhaseReceiptStore#{System.unique_integer([:positive])}")

    restarted_receipt_store_name =
      Module.concat(
        __MODULE__,
        "RecoveryPhaseReceiptStoreRestart#{System.unique_integer([:positive])}"
      )

    writer_name =
      Module.concat(__MODULE__, "RecoveryPhaseWriter#{System.unique_integer([:positive])}")

    subscriber_name =
      Module.concat(__MODULE__, "RecoveryPhaseSubscriber#{System.unique_integer([:positive])}")

    restarted_name =
      Module.concat(
        __MODULE__,
        "RecoveryPhaseSubscriberRestart#{System.unique_integer([:positive])}"
      )

    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path, core_node_id: "core_a", secret: "pipeline-secret", name: writer_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json", secret: "pipeline-secret", name: receipt_store_name}
      )

    subscriber =
      start_supervised!(
        {SnapshotSubscriber,
         room_id: "placeholder",
         pubsub_registry: pubsub_registry,
         mailbox_registry: mailbox_registry,
         mailbox_receipt_store: receipt_store,
         writer: writer,
         db_path: db_path,
         secret: "pipeline-secret",
         after_action_timeout_ms: 100,
         name: subscriber_name}
      )

    on_exit(fn -> cleanup_artifacts(db_path) end)

    assert {:ok, _} = CommandPublisher.subscribe("commands:io", registry_name: mailbox_registry)

    fixture = %{
      "snapshot_id" => "snap-recovery-#{phase}",
      "snapshot_seq" => 1,
      "snapshot_hash" => String.duplicate("f", 64),
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{"fan" => "fan-obs-1"},
      "source_observed_at" => %{},
      "source_received_seq" => %{"fan" => 1},
      "source_received_monotonic_ms" => %{"fan" => 1},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert :ok =
             PubSub.publish("io_state:room:placeholder", fixture, registry_name: pubsub_registry)

    assert_receive {:mailbox_command, "commands:io", delivery}, 1_000

    Process.exit(subscriber, :normal)
    Process.exit(receipt_store, :normal)
    Process.sleep(50)

    rewrite_receipt_phase(db_path <> ".receipts.json", delivery["receipt"]["receipt_id"], phase)

    restarted_receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: db_path <> ".receipts.json",
         secret: "pipeline-secret",
         name: restarted_receipt_store_name}
      )

    start_supervised!(
      {SnapshotSubscriber,
       room_id: "placeholder",
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: restarted_receipt_store,
       writer: writer,
       db_path: db_path,
       secret: "pipeline-secret",
       after_action_timeout_ms: 100,
       name: restarted_name}
    )

    refute_receive {:mailbox_command, "commands:io", _redelivery}, 200

    payload_json = wait_for_after_action_payload(db_path)
    payload = Contracts.decode_json!(payload_json)
    assert payload["command_id"] == delivery["command"]["command_id"]
    assert payload["status"] == "timed_out"
  end

  defp rewrite_receipt_phase(path, receipt_id, phase) do
    persisted = path |> File.read!() |> Contracts.decode_json!()

    updated =
      persisted
      |> put_in(["receipts", receipt_id, "delivery_phase"], phase)
      |> update_in(["receipts", receipt_id, "phase_metadata"], fn metadata ->
        metadata = metadata || %{}

        case phase do
          "receipt_stored" -> Map.take(metadata, ["receipt_stored_at"])
          "publish_attempted" -> Map.drop(metadata, ["accepted_at"])
          _ -> metadata
        end
      end)

    File.write!(path, Contracts.canonical_json(updated) <> "\n")
  end

  defp cleanup_artifacts(db_path) do
    File.rm(db_path)
    File.rm("#{db_path}-wal")
    File.rm("#{db_path}-shm")
    File.rm("#{db_path}.receipts.json")
    File.rm("#{db_path}.receipts.json.manifest.json")
  end
end

defmodule Eigenforge.Core.OodaPipelineTest.RetryReasoner do
  @moduledoc false

  alias Eigenforge.Contracts.ReasonerOutcome

  def reason(snapshot) do
    attempts =
      :ets.update_counter(
        :retry_reasoner_attempts,
        snapshot.snapshot_id,
        {2, 1},
        {snapshot.snapshot_id, 0}
      )

    if attempts == 1 do
      {:error, :transient_failure}
    else
      {:ok,
       ReasonerOutcome.new!(%{
         reasoner_outcome_id: "reasoner-retry",
         reasoner_id: "retry_reasoner",
         reasoner_version: "v1",
         snapshot_id: snapshot.snapshot_id,
         snapshot_hash: snapshot.snapshot_hash,
         outcome_type: "propose_action",
         target: "actuator:fan",
         requested_state: "on",
         reason: "retry succeeded",
         confidence_bps: 10_000,
         metadata: %{}
       })}
    end
  end
end
