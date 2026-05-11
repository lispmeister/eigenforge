defmodule Eigenforge.Dashboard.ReadModelTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.IoFaultStatusEvent
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.LedgerProjections
  alias Eigenforge.Dashboard.ReadModel

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-dashboard-#{System.unique_integer([:positive])}.sqlite3"
      )

    writer =
      start_supervised!(
        {LedgerWriter, db_path: db_path, core_node_id: "core_a", secret: "dashboard-secret", name: nil}
      )

    on_exit(fn ->
      File.rm(db_path)
      File.rm("#{db_path}-wal")
      File.rm("#{db_path}-shm")
    end)

    %{db_path: db_path, writer: writer}
  end

  test "builds a read-only dashboard snapshot from projections and recent ledger events", %{
    db_path: db_path,
    writer: writer
  } do
    assert :ok =
             LedgerProjections.observe_snapshot(db_path, %{
               "snapshot_id" => "snap-1",
               "snapshot_hash" => String.duplicate("a", 64),
               "room_id" => "placeholder",
               "co2_ppm" => 1200,
               "humidity_basis_points" => 4500,
               "temperature_millicelsius" => 22_000,
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

    assert {:ok, view} = ReadModel.snapshot(db_path, "placeholder")
    assert view["simulator_mode"]
    assert view["connection_status"] == "recovered"
    assert view["sensor_state"]["co2_ppm"] == 1200
    assert view["fan_state"]["status"] == "not_yet_observed"
    assert Enum.any?(view["recent_io_faults"], &(&1["payload"]["fault_type"] == "recovered"))

    assert {:ok, count_rows} = LedgerSQLite.query_json(db_path, "SELECT count(*) FROM ledger_events;")
    assert [%{"count(*)" => count}] = count_rows
    assert count >= 2
  end
end
