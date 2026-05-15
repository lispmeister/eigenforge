defmodule Eigenforge.IO.CommandExecutorTest do
  use ExUnit.Case, async: true

  alias Eigenforge.IO.CommandExecutionStore
  alias Eigenforge.IO.CommandExecutor

  defmodule StubTransport do
    @behaviour Eigenforge.IO.HomeAssistantClient.Transport

    @impl true
    def connect(_url, _token), do: {:ok, :stub_conn, %{}}

    @impl true
    def connect(url, token, _opts), do: connect(url, token)

    @impl true
    def command(_conn, request) do
      Process.put(:transport_request, request)
      {:ok, %{accepted: true}}
    end
  end

  setup do
    dir =
      Path.join(System.tmp_dir!(), "eigenforge-command-executor-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    store =
      start_supervised!(
        {CommandExecutionStore, path: Path.join(dir, "commands.json"), name: nil}
      )

    on_exit(fn -> File.rm_rf(dir) end)

    %{
      command_store: store,
      state: %{
        connected?: true,
        physical_control_enabled?: true,
        conn: :stub_conn,
        transport: StubTransport,
        home_assistant: %{entity_ids: %{fan: "switch.placeholder_fan"}},
        command_execution_store: store,
        hmac_secret: "command-secret",
        mailbox_receipt_store: nil,
        utc_now: fn -> ~U[2026-05-10 12:00:00.000Z] end,
        monotonic_now_ms: fn -> 1_000 end,
        started_at_utc: ~U[2026-05-10 12:00:00.000Z],
        started_monotonic_ms: 1_000,
        command_observer: self()
      }
    }
  end

  test "dispatches fan commands and records execution", %{state: state, command_store: store} do
    command = %{
      "command_id" => "cmd-1",
      "idempotency_key" => "idem-1",
      "effect_key" => "effect-1",
      "target" => "actuator:fan",
      "requested_state" => "on"
    }

    assert {:ok, %{accepted: true}} = CommandExecutor.execute(command, state)

    assert_receive {:transport_command, %{"domain" => "switch", "service" => "turn_on"}, %{accepted: true}}
    assert CommandExecutionStore.already_executed?(store, "idem-1")
  end

  test "dispatches stub targets without transport round-trips", %{state: state} do
    command = %{
      "command_id" => "cmd-2",
      "idempotency_key" => "idem-2",
      "effect_key" => "effect-2",
      "target" => "actuator:light",
      "requested_state" => "off"
    }

    assert {:ok, %{"result" => "noop_stub", "physical_io_performed" => false}} =
             CommandExecutor.execute(command, state)
  end

  test "rejects duplicate idempotency keys before dispatch", %{state: state, command_store: store} do
    command = %{
      "command_id" => "cmd-3",
      "idempotency_key" => "idem-3",
      "effect_key" => "effect-3",
      "target" => "actuator:fan",
      "requested_state" => "on"
    }

    assert :ok =
             CommandExecutionStore.record(store, %{
               idempotency_key: "idem-3",
               command_id: "cmd-prior",
               effect_key: "effect-prior",
               target: "actuator:fan",
               requested_state: "on",
               adapter_attempt_id: "adapter-attempt:cmd-prior",
               execution_status: "io_accepted",
               recorded_at: "2026-05-10T12:00:00.000Z"
             })

    assert {:error, :duplicate_idempotency_key} = CommandExecutor.execute(command, state)
    refute_received {:transport_command, _, _}
  end

  test "rejects unsupported targets", %{state: state} do
    command = %{
      "command_id" => "cmd-4",
      "idempotency_key" => "idem-4",
      "effect_key" => "effect-4",
      "target" => "actuator:toaster",
      "requested_state" => "on"
    }

    assert {:error, {:unsupported_target, "actuator:toaster"}} =
             CommandExecutor.execute(command, state)
  end
end
