defmodule Eigenforge.IO.HomeAssistantClientTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Core.IoFaultStatus
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.PubSub
  alias Eigenforge.IO.CommandExecutionStore
  alias Eigenforge.IO.HomeAssistantClient
  alias Eigenforge.Mailbox.CommandPublisher
  alias Eigenforge.Mailbox.ReceiptStore

  defmodule FlakyTransport do
    @behaviour Eigenforge.IO.HomeAssistantClient.Transport

    @impl true
    def connect(_url, _token) do
      counter = Process.get(:ha_connect_attempts, 0) + 1
      Process.put(:ha_connect_attempts, counter)

      if counter == 1 do
        {:error, :econnrefused}
      else
        {:ok, :fake_conn, valid_states()}
      end
    end

    @impl true
    def connect(url, token, _opts), do: connect(url, token)

    @impl true
    def command(_conn, _request) do
      {:ok, %{accepted: true}}
    end

    def valid_states do
      %{
        "sensor.placeholder_co2" => %{
          "entity_id" => "sensor.placeholder_co2",
          "entity_class" => "sensor",
          "state" => "1200",
          "observation_id" => "co2-1",
          "observed_at" => "2026-05-10T12:00:00.000Z",
          "received_seq" => 10,
          "received_monotonic_ms" => 100,
          "status" => "fresh"
        },
        "sensor.placeholder_humidity" => %{
          "entity_id" => "sensor.placeholder_humidity",
          "entity_class" => "sensor",
          "state" => "45.0",
          "observation_id" => "humidity-1",
          "observed_at" => "2026-05-10T12:00:00.000Z",
          "received_seq" => 10,
          "received_monotonic_ms" => 100,
          "status" => "fresh"
        },
        "sensor.placeholder_temperature" => %{
          "entity_id" => "sensor.placeholder_temperature",
          "entity_class" => "sensor",
          "state" => "22.0",
          "observation_id" => "temperature-1",
          "observed_at" => "2026-05-10T12:00:00.000Z",
          "received_seq" => 10,
          "received_monotonic_ms" => 100,
          "status" => "fresh"
        },
        "switch.placeholder_fan" => %{
          "entity_id" => "switch.placeholder_fan",
          "entity_class" => "switch",
          "state" => "off",
          "observation_id" => "fan-1",
          "observed_at" => "2026-05-10T12:00:00.000Z",
          "received_seq" => 10,
          "received_monotonic_ms" => 100,
          "status" => "fresh"
        }
      }
    end
  end

  defmodule WrongClassTransport do
    @behaviour Eigenforge.IO.HomeAssistantClient.Transport

    @impl true
    def connect(_url, _token) do
      {:ok, :fake_conn,
       %{
         "sensor.placeholder_co2" => %{
           "entity_id" => "sensor.placeholder_co2",
           "entity_class" => "switch"
         },
         "sensor.placeholder_humidity" => %{
           "entity_id" => "sensor.placeholder_humidity",
           "entity_class" => "sensor"
         },
         "sensor.placeholder_temperature" => %{
           "entity_id" => "sensor.placeholder_temperature",
           "entity_class" => "sensor"
         },
         "switch.placeholder_fan" => %{
           "entity_id" => "switch.placeholder_fan",
           "entity_class" => "switch"
         }
       }}
    end

    @impl true
    def connect(url, token, _opts), do: connect(url, token)

    @impl true
    def command(_conn, _request), do: {:ok, %{accepted: true}}
  end

  defmodule FailingCommandTransport do
    @behaviour Eigenforge.IO.HomeAssistantClient.Transport

    @impl true
    def connect(_url, _token), do: {:ok, :fake_conn, FlakyTransport.valid_states()}

    @impl true
    def connect(url, token, _opts), do: connect(url, token)

    @impl true
    def command(_conn, _request), do: {:error, :service_unavailable}
  end

  defmodule DownTransport do
    @behaviour Eigenforge.IO.HomeAssistantClient.Transport

    @impl true
    def connect(_url, _token), do: {:error, :econnrefused}

    @impl true
    def connect(url, token, _opts), do: connect(url, token)

    @impl true
    def command(_conn, _request), do: {:error, :not_connected}
  end

  defmodule ConnectedTransport do
    @behaviour Eigenforge.IO.HomeAssistantClient.Transport

    @impl true
    def connect(_url, _token), do: {:ok, :fake_conn, FlakyTransport.valid_states()}

    @impl true
    def connect(url, token, _opts), do: connect(url, token)

    @impl true
    def command(_conn, _request), do: {:ok, %{accepted: true}}
  end

  setup do
    Process.delete(:ha_connect_attempts)

    dir =
      Path.join(System.tmp_dir!(), "eigenforge-ha-client-#{System.unique_integer([:positive])}")

    db_path = Path.join(dir, "core.sqlite3")
    log_path = Path.join(dir, "io_fault_status.log")

    pubsub_registry =
      Module.concat(__MODULE__, "CoreRegistry#{System.unique_integer([:positive])}")

    mailbox_registry =
      Module.concat(__MODULE__, "MailboxRegistry#{System.unique_integer([:positive])}")

    fault_registry =
      Module.concat(__MODULE__, "FaultRegistry#{System.unique_integer([:positive])}")

    receipt_store_name =
      Module.concat(__MODULE__, "ReceiptStore#{System.unique_integer([:positive])}")

    command_store_name =
      Module.concat(__MODULE__, "CommandStore#{System.unique_integer([:positive])}")

    io_fault_status_name =
      Module.concat(__MODULE__, "IoFaultStatus#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    start_supervised!({Registry, keys: :duplicate, name: pubsub_registry})
    start_supervised!({Registry, keys: :duplicate, name: mailbox_registry})
    start_supervised!({Registry, keys: :duplicate, name: fault_registry})

    writer =
      start_supervised!(
        {LedgerWriter, db_path: db_path, core_node_id: "core_a", secret: "ha-secret", name: nil}
      )

    io_fault_status =
      start_supervised!(
        {IoFaultStatus,
         log_path: log_path,
         hmac_secret: "ha-secret",
         default_room_id: "placeholder",
         writer: writer,
         registry_name: fault_registry,
         name: io_fault_status_name}
      )

    receipt_store =
      start_supervised!(
        {ReceiptStore,
         path: Path.join(dir, "receipts.json"), secret: "ha-secret", name: receipt_store_name}
      )

    command_store =
      start_supervised!(
        {CommandExecutionStore,
         path: Path.join(dir, "command_store.json"), name: command_store_name}
      )

    on_exit(fn -> File.rm_rf(dir) end)

    %{
      db_path: db_path,
      log_path: log_path,
      pubsub_registry: pubsub_registry,
      mailbox_registry: mailbox_registry,
      fault_registry: fault_registry,
      io_fault_status: io_fault_status,
      receipt_store: receipt_store,
      command_store: command_store,
      entity_ids: %{
        co2: "sensor.placeholder_co2",
        humidity: "sensor.placeholder_humidity",
        temperature: "sensor.placeholder_temperature",
        fan: "switch.placeholder_fan"
      }
    }
  end

  test "starts degraded, retries, recovers, publishes a snapshot, and dispatches fan commands", %{
    db_path: db_path,
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    assert {:ok, _} =
             PubSub.subscribe("io_state:room:placeholder", registry_name: pubsub_registry)

    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: FlakyTransport,
       name: Module.concat(__MODULE__, "Client#{System.unique_integer([:positive])}")}
    )

    assert_receive {:core_pubsub, "io_state:room:placeholder", snapshot}, 2_500
    assert snapshot.snapshot_id
    assert snapshot.co2_ppm == 1200

    assert :ok =
             CommandPublisher.publish(
               "commands:io",
               signed_command("cmd-1", "actuator:fan", "on"),
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 5,
               ledger_event_hash: String.duplicate("a", 64),
               decision_event_id: "event-4"
             )

    assert_receive {:transport_command,
                    %{"service" => "turn_on", "entity_id" => "switch.placeholder_fan"},
                    %{accepted: true}},
                   1_500

    assert {:ok, rows} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT event_type FROM ledger_events ORDER BY sequence ASC;"
             )

    event_types = Enum.map(rows, & &1["event_type"])
    assert "connection_status_observed" in event_types
  end

  test "wrong-class entities enter degraded mode and disable physical fan control", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: WrongClassTransport,
       name: Module.concat(__MODULE__, "WrongClassClient#{System.unique_integer([:positive])}")}
    )

    Process.sleep(100)

    assert :ok =
             CommandPublisher.publish(
               "commands:io",
               signed_command("cmd-2", "actuator:fan", "off"),
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 6,
               ledger_event_hash: String.duplicate("b", 64),
               decision_event_id: "event-4"
             )

    refute_receive {:transport_command, _request}, 300

    assert "publish_attempted" == latest_receipt_phase(receipt_store, "cmd-2")
  end

  test "non-fan actuator commands stay noop stubs", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: FlakyTransport,
       name: Module.concat(__MODULE__, "StubClient#{System.unique_integer([:positive])}")}
    )

    assert :ok =
             CommandPublisher.publish(
               "commands:io",
               signed_command("cmd-3", "actuator:light", "on"),
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 7,
               ledger_event_hash: String.duplicate("c", 64),
               decision_event_id: "event-4"
             )

    refute_receive {:transport_command, _request}, 300
  end

  test "rejects duplicate idempotency keys after the first accepted execution", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    fault_registry: fault_registry,
    log_path: log_path,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: FlakyTransport,
       name: Module.concat(__MODULE__, "ReplayClient#{System.unique_integer([:positive])}")}
    )

    Process.sleep(1_200)
    assert {:ok, _} = IoFaultStatus.subscribe(fault_registry)

    command = signed_command("cmd-dup", "actuator:fan", "on")

    assert :ok =
             CommandPublisher.publish("commands:io", command,
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 8,
               ledger_event_hash: String.duplicate("d", 64),
               decision_event_id: "event-4"
             )

    assert_receive {:transport_command, _request, %{accepted: true}}, 2_000

    assert :ok =
             CommandPublisher.publish("commands:io", command,
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 9,
               ledger_event_hash: String.duplicate("e", 64),
               decision_event_id: "event-4"
             )

    refute_receive {:transport_command, _request, %{accepted: true}}, 500
    assert_fault_logged(log_path, "duplicate_idempotency_key")
    assert "publish_attempted" == latest_receipt_phase(receipt_store, "cmd-dup")
  end

  test "transport failures keep the receipt phase at publish_attempted", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: FailingCommandTransport,
       name: Module.concat(__MODULE__, "FailingClient#{System.unique_integer([:positive])}")}
    )

    Process.sleep(100)

    assert :ok =
             CommandPublisher.publish(
               "commands:io",
               signed_command("cmd-fail", "actuator:fan", "on"),
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 10,
               ledger_event_hash: String.duplicate("f", 64),
               decision_event_id: "event-4"
             )

    refute_receive {:transport_command, _request, _result}, 300
    assert "publish_attempted" == latest_receipt_phase(receipt_store, "cmd-fail")
  end

  test "disconnected clients keep the receipt phase at publish_attempted", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: DownTransport,
       name: Module.concat(__MODULE__, "DownClient#{System.unique_integer([:positive])}")}
    )

    assert :ok =
             CommandPublisher.publish(
               "commands:io",
               signed_command("cmd-down", "actuator:fan", "on"),
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 11,
               ledger_event_hash: String.duplicate("0", 64),
               decision_event_id: "event-4"
             )

    refute_receive {:transport_command, _request, _result}, 300
    assert "publish_attempted" == latest_receipt_phase(receipt_store, "cmd-down")
  end

  test "wall-clock jumps do not expire in-flight commands before their monotonic deadline", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    fault_registry: fault_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    {:ok, clock} =
      Agent.start_link(fn ->
        %{
          utc: ~U[2026-05-10 12:00:00.000Z],
          monotonic: 1_000
        }
      end)

    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: FlakyTransport,
       utc_now: fn -> Agent.get(clock, & &1.utc) end,
       monotonic_now_ms: fn -> Agent.get(clock, & &1.monotonic) end,
       name: Module.concat(__MODULE__, "ClockClient#{System.unique_integer([:positive])}")}
    )

    Process.sleep(1_200)
    assert {:ok, _} = IoFaultStatus.subscribe(fault_registry)

    Agent.update(clock, fn _ ->
      %{
        utc: ~U[2101-05-10 12:00:00.000Z],
        monotonic: 1_250
      }
    end)

    assert :ok =
             CommandPublisher.publish(
               "commands:io",
               signed_command("cmd-clock", "actuator:fan", "on",
                 expires_at: "2026-05-10T12:00:05.000Z"
               ),
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 12,
               ledger_event_hash: String.duplicate("1", 64),
               decision_event_id: "event-4"
             )

    assert_receive {:transport_command, %{"service" => "turn_on"}, %{accepted: true}}, 2_000
  end

  test "initial snapshots use the injected canonical UTC timestamp", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    assert {:ok, _} =
             PubSub.subscribe("io_state:room:placeholder", registry_name: pubsub_registry)

    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: FlakyTransport,
       utc_now: fn -> ~U[2026-05-10 12:34:56.789Z] end,
       name: Module.concat(__MODULE__, "TimestampClient#{System.unique_integer([:positive])}")}
    )

    assert_receive {:core_pubsub, "io_state:room:placeholder", snapshot}, 2_500
    assert snapshot.normalized_at == "2026-05-10T12:34:56.789Z"
  end

  test "commands expire after their monotonic deadline even if wall time moves backward", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    log_path: log_path,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    {:ok, clock} =
      Agent.start_link(fn ->
        %{
          utc: ~U[2026-05-10 12:00:00.000Z],
          monotonic: 1_000
        }
      end)

    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: FlakyTransport,
       utc_now: fn -> Agent.get(clock, & &1.utc) end,
       monotonic_now_ms: fn -> Agent.get(clock, & &1.monotonic) end,
       name: Module.concat(__MODULE__, "ExpiredClockClient#{System.unique_integer([:positive])}")}
    )

    Process.sleep(1_200)

    Agent.update(clock, fn _ ->
      %{
        utc: ~U[2026-05-10 11:59:00.000Z],
        monotonic: 7_500
      }
    end)

    assert :ok =
             CommandPublisher.publish(
               "commands:io",
               signed_command("cmd-expired", "actuator:fan", "on",
                 expires_at: "2026-05-10T12:00:05.000Z"
               ),
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 15,
               ledger_event_hash: String.duplicate("4", 64),
               decision_event_id: "event-4"
             )

    refute_receive {:transport_command, %{"service" => "turn_on"}, %{accepted: true}}, 500
    assert_fault_logged(log_path, "command_expired")
    assert "publish_attempted" == latest_receipt_phase(receipt_store, "cmd-expired")
  end

  test "receipts missing committed ledger references are rejected", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    fault_registry: fault_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: FlakyTransport,
       name: Module.concat(__MODULE__, "BadReceiptClient#{System.unique_integer([:positive])}")}
    )

    Process.sleep(1_200)
    assert {:ok, _} = IoFaultStatus.subscribe(fault_registry)

    assert {:ok, receipt} =
             ReceiptStore.store_receipt(
               receipt_store,
               "commands:io",
               signed_command("cmd-bad", "actuator:fan", "on") |> Contracts.signable_map(),
               ledger_sequence: 13,
               ledger_event_hash: String.duplicate("2", 64),
               decision_event_id: "event-4"
             )

    assert :ok =
             ReceiptStore.mark_phase(receipt_store, receipt.receipt_id, "publish_attempted", %{
               published_at: receipt.delivered_at
             })

    assert {:ok, entry} = ReceiptStore.fetch(receipt_store, receipt.receipt_id)
    bad_receipt = put_in(entry, ["receipt", "ledger_event_hash"], "")

    Registry.dispatch(mailbox_registry, "commands:io", fn entries ->
      Enum.each(entries, fn {pid, _value} ->
        send(
          pid,
          {:mailbox_command, "commands:io",
           %{
             "command" => wire_command(signed_command("cmd-bad", "actuator:fan", "on")),
             "receipt" => bad_receipt["receipt"]
           }}
        )
      end)
    end)

    refute_receive {:transport_command, _request, _result}, 500
    assert "publish_attempted" == latest_receipt_phase(receipt_store, "cmd-bad")
  end

  test "invalid command signatures and receipt mismatches are rejected before dispatch", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    fault_registry: fault_registry,
    log_path: log_path,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    client =
      start_supervised!(
        {HomeAssistantClient,
         room_id: "placeholder",
         home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
         hmac_secret: "ha-secret",
         ha_reconnect_max_ms: 1_000,
         io_fault_status: io_fault_status,
         pubsub_registry: pubsub_registry,
         mailbox_registry: mailbox_registry,
         mailbox_receipt_store: receipt_store,
         command_execution_store: command_store,
         command_observer: self(),
         transport: ConnectedTransport,
         name: Module.concat(__MODULE__, "MismatchClient#{System.unique_integer([:positive])}")}
      )

    Process.sleep(100)
    assert {:ok, _} = IoFaultStatus.subscribe(fault_registry)

    command = signed_command("cmd-invalid", "actuator:fan", "on")

    assert {:ok, receipt} =
             ReceiptStore.store_receipt(
               receipt_store,
               "commands:io",
               Contracts.signable_map(command),
               ledger_sequence: 16,
               ledger_event_hash: String.duplicate("5", 64),
               decision_event_id: command.decision_event_id
             )

    assert :ok =
             ReceiptStore.mark_phase(receipt_store, receipt.receipt_id, "publish_attempted", %{
               published_at: receipt.delivered_at
             })

    assert {:ok, entry} = ReceiptStore.fetch(receipt_store, receipt.receipt_id)

    bad_command = Map.put(wire_command(command), "signature", "tampered-signature")

    bad_receipt_command =
      entry["receipt"]
      |> Map.put("command_id", "cmd-other")
      |> Map.put("signature", "")
      |> then(
        &Map.put(
          &1,
          "signature",
          Contracts.sign_hmac(&1, "ha-secret", "eigenforge:v1:delivery_receipt")
        )
      )

    bad_receipt_decision =
      entry["receipt"]
      |> Map.put("decision_event_id", "event-other")
      |> Map.put("signature", "")
      |> then(
        &Map.put(
          &1,
          "signature",
          Contracts.sign_hmac(&1, "ha-secret", "eigenforge:v1:delivery_receipt")
        )
      )

    send(
      client,
      {:mailbox_command, "commands:io",
       %{"command" => bad_command, "receipt" => entry["receipt"]}}
    )

    send(
      client,
      {:mailbox_command, "commands:io",
       %{"command" => wire_command(command), "receipt" => bad_receipt_command}}
    )

    send(
      client,
      {:mailbox_command, "commands:io",
       %{"command" => wire_command(command), "receipt" => bad_receipt_decision}}
    )

    refute_receive {:transport_command, _request, _result}, 500
    refute_receive {:transport_command, _request, _result}, 100
    refute_receive {:transport_command, _request, _result}, 100

    assert_fault_logged(log_path, "invalid_command_signature")

    assert "publish_attempted" == latest_receipt_phase(receipt_store, "cmd-invalid")
  end

  test "degraded command execution stores block physical execution after restart", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    entity_ids: entity_ids
  } do
    command_store_name =
      Module.concat(__MODULE__, "CorruptCommandStore#{System.unique_integer([:positive])}")

    path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-command-store-corrupt-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, ~s({"format_version":"json-canonical-v0","entries":{}}))

    corrupt_store =
      start_supervised!({CommandExecutionStore, path: path, name: command_store_name})

    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: corrupt_store,
       command_observer: self(),
       transport: FlakyTransport,
       name: Module.concat(__MODULE__, "CorruptStoreClient#{System.unique_integer([:positive])}")}
    )

    Process.sleep(1_200)

    assert :ok =
             CommandPublisher.publish(
               "commands:io",
               signed_command("cmd-store", "actuator:fan", "on"),
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 14,
               ledger_event_hash: String.duplicate("3", 64),
               decision_event_id: "event-4"
             )

    refute_receive {:transport_command, _request, _result}, 500
    assert "publish_attempted" == latest_receipt_phase(receipt_store, "cmd-store")
  end

  test "persisted duplicate idempotency keys are rejected after restart", %{
    pubsub_registry: pubsub_registry,
    mailbox_registry: mailbox_registry,
    io_fault_status: io_fault_status,
    receipt_store: receipt_store,
    command_store: command_store,
    entity_ids: entity_ids
  } do
    client_name = Module.concat(__MODULE__, "RestartClient#{System.unique_integer([:positive])}")

    client =
      start_supervised!(
        {HomeAssistantClient,
         room_id: "placeholder",
         home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
         hmac_secret: "ha-secret",
         ha_reconnect_max_ms: 1_000,
         io_fault_status: io_fault_status,
         pubsub_registry: pubsub_registry,
         mailbox_registry: mailbox_registry,
         mailbox_receipt_store: receipt_store,
         command_execution_store: command_store,
         command_observer: self(),
         transport: ConnectedTransport,
         name: client_name}
      )

    Process.sleep(100)

    command = signed_command("cmd-restart-dup", "actuator:fan", "on")

    assert :ok =
             CommandPublisher.publish("commands:io", command,
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 17,
               ledger_event_hash: String.duplicate("6", 64),
               decision_event_id: "event-4"
             )

    assert_receive {:transport_command, _request, %{accepted: true}}, 2_000

    Process.exit(client, :normal)
    Process.sleep(50)

    restarted_name =
      Module.concat(__MODULE__, "RestartClientReused#{System.unique_integer([:positive])}")

    start_supervised!(
      {HomeAssistantClient,
       room_id: "placeholder",
       home_assistant: %{url: "http://ha.local", token: "token", entity_ids: entity_ids},
       hmac_secret: "ha-secret",
       ha_reconnect_max_ms: 1_000,
       io_fault_status: io_fault_status,
       pubsub_registry: pubsub_registry,
       mailbox_registry: mailbox_registry,
       mailbox_receipt_store: receipt_store,
       command_execution_store: command_store,
       command_observer: self(),
       transport: ConnectedTransport,
       name: restarted_name}
    )

    Process.sleep(100)

    assert :ok =
             CommandPublisher.publish("commands:io", command,
               registry_name: mailbox_registry,
               receipt_store: receipt_store,
               ledger_sequence: 18,
               ledger_event_hash: String.duplicate("7", 64),
               decision_event_id: "event-4"
             )

    refute_receive {:transport_command, _request, %{accepted: true}}, 500
    assert "publish_attempted" == latest_receipt_phase(receipt_store, "cmd-restart-dup")
  end

  defp signed_command(command_id, target, requested_state, opts \\ []) do
    expires_at = Keyword.get(opts, :expires_at, "2099-05-10T12:00:07.000Z")

    CommandEnvelope.new!(%{
      command_id: command_id,
      idempotency_key: "idem-#{command_id}",
      effect_key: "effect-#{command_id}",
      subject: "core_rule_stub",
      target: target,
      action: "command_actuator",
      scope: "room:placeholder",
      requested_state: requested_state,
      snapshot_id: "snap-1",
      snapshot_seq: 1,
      decision_event_id: "event-4",
      reasoner_outcome_event_id: "event-2",
      capability_event_id: "event-3",
      policy_decision_id: "policy-1",
      issued_at: "2026-05-10T12:00:02.000Z",
      expires_at: expires_at,
      payload_hash: String.duplicate("c", 64),
      signature_version: "hmac-sha256-v1",
      signature: ""
    })
    |> then(fn unsigned ->
      %{
        unsigned
        | signature: Contracts.sign_hmac(unsigned, "ha-secret", "eigenforge:v1:command_envelope")
      }
    end)
  end

  defp latest_receipt_phase(receipt_store, command_id) do
    assert {:ok, entries} = ReceiptStore.entries_for_command(receipt_store, command_id)

    entries
    |> Enum.max_by(fn entry ->
      get_in(entry, ["phase_metadata", "published_at"]) ||
        get_in(entry, ["phase_metadata", "receipt_stored_at"])
    end)
    |> Map.fetch!("delivery_phase")
  end

  defp assert_fault_logged(log_path, fault_type, attempts \\ 100)
       when is_binary(log_path) and is_binary(fault_type) and attempts >= 0 do
    case File.read(log_path) do
      {:ok, body} ->
        if body =~ fault_type do
          :ok
        else
          if attempts > 0 do
            Process.sleep(50)
            assert_fault_logged(log_path, fault_type, attempts - 1)
          else
            flunk("expected fault log to include #{inspect(fault_type)}, got: #{body}")
          end
        end

      {:error, reason} ->
        if attempts > 0 do
          Process.sleep(50)
          assert_fault_logged(log_path, fault_type, attempts - 1)
        else
          flunk("expected fault log to be readable, got: #{inspect(reason)}")
        end
    end
  end

  defp wire_command(command) do
    command
    |> Map.from_struct()
    |> Map.delete(:__struct__)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end
end
