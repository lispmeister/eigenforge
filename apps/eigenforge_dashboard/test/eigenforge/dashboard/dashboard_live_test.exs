defmodule Eigenforge.Dashboard.DashboardLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.IoFaultStatusEvent
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerProjections
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Dashboard.Endpoint

  @endpoint Endpoint

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-dashboard-live-#{System.unique_integer([:positive])}.sqlite3"
      )

    writer =
      start_supervised!(
        {LedgerWriter, db_path: db_path, core_node_id: "core_a", secret: "replace_me", name: nil}
      )

    Application.put_env(:eigenforge_core, :runtime_env, %{
      "EIGENFORGE_IO_MODE" => "simulator",
      "EIGENFORGE_HMAC_SECRET" => "replace_me",
      "EIGENFORGE_CORE_NODE_ID" => "core_a",
      "EIGENFORGE_CORE_DB_PATH" => db_path,
      "EIGENFORGE_DEVICE_INVENTORY_PATH" => Path.expand("../../../../../config/devices.json", __DIR__),
      "EIGENFORGE_DEVICE_INVENTORY_SIG_PATH" => Path.expand("../../../../../config/devices.json.sig", __DIR__),
      "EIGENFORGE_CAPABILITY_GRANTS_DIR" => Path.expand("../../../../../config/capabilities", __DIR__),
      "EIGENFORGE_SIMULATOR_SNAPSHOTS_DIR" => Path.expand("../../../../../config/simulator_snapshots", __DIR__),
      "EIGENFORGE_IO_FAULT_STATUS_LOG" => Path.join(System.tmp_dir!(), "dashboard-live.log")
    })

    assert :ok =
             LedgerProjections.observe_snapshot(db_path, %{
               "snapshot_id" => "snap-live",
               "snapshot_hash" => String.duplicate("a", 64),
               "room_id" => "placeholder",
               "co2_ppm" => 1200,
               "humidity_basis_points" => 4500,
               "temperature_millicelsius" => 22000,
               "fan_state" => "off",
               "source_status" => %{
                 "co2" => "fresh",
                 "humidity" => "fresh",
                 "temperature" => "fresh",
                 "fan" => "not_yet_observed"
               },
               "normalized_at" => "2026-05-10T12:00:00.000Z",
               "freshness" => "fresh"
             }, io_mode: "simulator")

    assert {:ok, _} =
             LedgerWriter.append(writer, %{
               event_type: "connection_status_observed",
               subject: "io_adapter",
               source_app: "eigenforge_core",
               payload:
                 Contracts.signable_map(
                   IoFaultStatusEvent.new!(%{
                     event_id: "fault-1",
                     room_id: "placeholder",
                     source: "simulator",
                     fault_type: "recovered",
                     observed_at: "2026-05-10T12:00:00.000Z",
                     metadata: %{}
                   })
                 )
             })

    on_exit(fn ->
      Application.delete_env(:eigenforge_core, :runtime_env)
      File.rm(db_path)
      File.rm("#{db_path}-wal")
      File.rm("#{db_path}-shm")
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  test "renders a read-only dashboard from the local projections", %{conn: conn} do
    assert {:ok, [%{"count(*)" => count_before}]} =
             LedgerSQLite.query_json(
               Application.fetch_env!(:eigenforge_core, :runtime_env)["EIGENFORGE_CORE_DB_PATH"],
               "SELECT count(*) FROM ledger_events;"
             )

    assert {:ok, _view, html} = live(conn, "/")
    assert html =~ "Read-only control surface"
    assert html =~ "1200 ppm"
    assert html =~ "recovered"
    assert html =~ "No recent ledger events yet" or html =~ "Recent Ledger Events"

    assert {:ok, [%{"count(*)" => count_after}]} =
             LedgerSQLite.query_json(
               Application.fetch_env!(:eigenforge_core, :runtime_env)["EIGENFORGE_CORE_DB_PATH"],
               "SELECT count(*) FROM ledger_events;"
             )

    assert count_after == count_before
  end
end
