defmodule Eigenforge.Core.IoFaultStatusTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.IoFaultStatus
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerTooling
  alias Eigenforge.Core.LedgerWriter

  setup do
    dir = Path.join(System.tmp_dir!(), "eigenforge-io-fault-#{System.unique_integer([:positive])}")
    db_path = Path.join(dir, "core.sqlite3")
    log_path = Path.join(dir, "io_fault_status.log")
    registry_name = Module.concat(__MODULE__, "Registry#{System.unique_integer([:positive])}")
    writer_name = Module.concat(__MODULE__, "Writer#{System.unique_integer([:positive])}")
    io_fault_status_name = Module.concat(__MODULE__, "IoFaultStatus#{System.unique_integer([:positive])}")
    secret = "io-fault-secret"

    File.mkdir_p!(dir)

    start_supervised!({Registry, keys: :duplicate, name: registry_name})

    writer =
      start_supervised!(
        {LedgerWriter, db_path: db_path, core_node_id: "core_a", secret: secret, name: writer_name}
      )

    io_fault_status =
      start_supervised!(
        {IoFaultStatus,
         log_path: log_path,
         hmac_secret: secret,
         home_assistant_token: "ha-token-secret",
         default_room_id: "placeholder",
         writer: writer,
         registry_name: registry_name,
         name: io_fault_status_name}
      )

    on_exit(fn -> File.rm_rf(dir) end)

    %{
      db_path: db_path,
      log_path: log_path,
      registry_name: registry_name,
      writer: writer,
      io_fault_status: io_fault_status,
      secret: secret
    }
  end

  test "publishes, redacts, logs, and persists connection transitions", %{
    db_path: db_path,
    log_path: log_path,
    registry_name: registry_name,
    io_fault_status: io_fault_status,
    secret: secret
  } do
    assert {:ok, _} = IoFaultStatus.subscribe(registry_name)

    assert {:ok, event} =
             IoFaultStatus.record(io_fault_status, %{
               source: "home_assistant",
               fault_type: "connection_down",
               correlation_id: "ha-conn-1",
               message: "adapter failed with ha-token-secret",
               metadata: %{"detail" => "secret io-fault-secret in payload"}
             })

    assert_receive {:io_fault_status, published}
    assert published.event_id == event.event_id
    assert published.fault_type == "connection_down"

    log_body = File.read!(log_path)
    assert log_body =~ "[REDACTED]"
    refute log_body =~ "ha-token-secret"
    refute log_body =~ secret

    assert {:ok, rows} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT sequence, event_type FROM ledger_events ORDER BY sequence ASC;"
             )

    assert Enum.map(rows, & &1["event_type"]) == ["ledger_genesis", "connection_status_observed"]
    assert :ok = LedgerTooling.verify(db_path, "core_a", secret)
  end

  test "redacts sensitive key names in log payloads even when only the field name is sensitive", %{
    log_path: log_path,
    io_fault_status: io_fault_status
  } do
    assert {:ok, _event} =
             IoFaultStatus.record(io_fault_status, %{
               source: "home_assistant",
               fault_type: "adapter_execution_failed",
               metadata: %{
                 "HOME_ASSISTANT_TOKEN" => "raw-token",
                 "nested" => %{"password" => "raw-password"}
               },
               audit: true
             })

    log_body = File.read!(log_path)
    refute log_body =~ "raw-token"
    refute log_body =~ "raw-password"
    assert log_body =~ "[REDACTED]"
  end

  test "connection transitions persist only once per correlation", %{
    db_path: db_path,
    io_fault_status: io_fault_status
  } do
    assert {:ok, _event} =
             IoFaultStatus.record(io_fault_status, %{
               source: "home_assistant",
               fault_type: "reconnecting",
               correlation_id: "ha-conn-2"
             })

    assert {:ok, _event} =
             IoFaultStatus.record(io_fault_status, %{
               source: "home_assistant",
               fault_type: "reconnecting",
               correlation_id: "ha-conn-2"
             })

    assert {:ok, rows} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT event_type FROM ledger_events ORDER BY sequence ASC;"
             )

    assert Enum.map(rows, & &1["event_type"]) == ["ledger_genesis", "connection_status_observed"]
  end

  test "non-connection faults stay out of the ledger unless promoted", %{
    db_path: db_path,
    io_fault_status: io_fault_status
  } do
    assert {:ok, _event} =
             IoFaultStatus.record(io_fault_status, %{
               source: "home_assistant",
               fault_type: "malformed_observation",
               metadata: %{"entity_id" => "sensor.co2"}
             })

    assert {:ok, rows} =
             LedgerSQLite.query_json(db_path, "SELECT event_type FROM ledger_events ORDER BY sequence ASC;")

    assert Enum.map(rows, & &1["event_type"]) == ["ledger_genesis"]
  end

  test "promoted faults are persisted for audit", %{db_path: db_path, io_fault_status: io_fault_status} do
    assert {:ok, _event} =
             IoFaultStatus.record(io_fault_status, %{
               source: "home_assistant",
               fault_type: "adapter_execution_failed",
               metadata: %{"entity_id" => "switch.vent_fan"},
               audit: true
             })

    assert {:ok, rows} =
             LedgerSQLite.query_json(db_path, "SELECT event_type FROM ledger_events ORDER BY sequence ASC;")

    assert Enum.map(rows, & &1["event_type"]) == ["ledger_genesis", "io_fault_observed"]
  end
end
