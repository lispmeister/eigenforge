defmodule Eigenforge.IO.AdapterSupervisorTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.IO.AdapterSupervisor

  test "starts the simulator client under the adapter supervisor" do
    dir =
      Path.join(System.tmp_dir!(), "eigenforge-adapter-supervisor-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf(dir) end)

    config = %RuntimeConfig{
      io_mode: :simulator,
      simulator_snapshots_dir: dir
    }

    supervisor = start_supervised!({AdapterSupervisor, [config: config, name: nil]})

    assert [{_id, pid, :worker, [Eigenforge.IO.SimulatorClient]}] =
             Supervisor.which_children(supervisor)

    assert Process.alive?(pid)
  end
end
