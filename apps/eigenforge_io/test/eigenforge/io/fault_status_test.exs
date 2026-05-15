defmodule Eigenforge.IO.FaultStatusTest do
  use ExUnit.Case, async: true

  alias Eigenforge.IO.FaultStatus

  test "publishes a lightweight event and writes the debug log" do
    dir =
      Path.join(System.tmp_dir!(), "eigenforge-io-fault-status-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf(dir) end)

    registry_name = Module.concat(__MODULE__, "Registry#{System.unique_integer([:positive])}")
    server_name = Module.concat(__MODULE__, "Server#{System.unique_integer([:positive])}")
    log_path = Path.join(dir, "io_fault_status.log")

    start_supervised!({Registry, keys: :duplicate, name: registry_name})

    server =
      start_supervised!(
        {FaultStatus,
         log_path: log_path,
         hmac_secret: "io-secret",
         home_assistant_token: "ha-secret",
         default_room_id: "placeholder",
         registry_name: registry_name,
         name: server_name}
      )

    assert {:ok, _} = FaultStatus.subscribe(registry_name)

    assert {:ok, event} =
             FaultStatus.record(server, %{
               source: "simulator",
               room_id: "placeholder",
               fault_type: "connection_down",
               message: "adapter unavailable",
               metadata: %{"correlation_id" => "corr-1"}
             })

    assert_receive {:io_fault_status, published}
    assert published.event_id == event.event_id
    assert published.room_id == "placeholder"
    assert published.fault_type == "connection_down"

    log_body = File.read!(log_path)
    assert log_body =~ "connection_down"
    assert log_body =~ "placeholder"
  end
end
