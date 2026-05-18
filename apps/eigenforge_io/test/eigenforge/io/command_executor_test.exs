defmodule Eigenforge.IO.CommandExecutorTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Contracts.DeliveryReceipt
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
      Path.join(
        System.tmp_dir!(),
        "eigenforge-command-executor-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    store =
      start_supervised!(
        {CommandExecutionStore,
         path: Path.join(dir, "commands.json"), secret: "command-secret", name: nil}
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
    delivery = verified_delivery("cmd-1", "idem-1", "effect-1", "actuator:fan", "on", 1)

    assert {:ok, %{accepted: true}} = CommandExecutor.execute(delivery, state)

    assert_receive {:transport_command, %{"domain" => "switch", "service" => "turn_on"},
                    %{accepted: true}}

    assert CommandExecutionStore.already_executed?(store, "idem-1")
  end

  test "dispatches stub targets without transport round-trips", %{state: state} do
    delivery = verified_delivery("cmd-2", "idem-2", "effect-2", "actuator:light", "off", 2)

    assert {:ok, %{"result" => "noop_stub", "physical_io_performed" => false}} =
             CommandExecutor.execute(delivery, state)
  end

  test "rejects duplicate idempotency keys before dispatch", %{state: state, command_store: store} do
    delivery = verified_delivery("cmd-3", "idem-3", "effect-3", "actuator:fan", "on", 3)

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

    assert {:error, :duplicate_idempotency_key} = CommandExecutor.execute(delivery, state)
    refute_received {:transport_command, _, _}
  end

  test "rejects unsupported targets", %{state: state} do
    delivery = verified_delivery("cmd-4", "idem-4", "effect-4", "actuator:toaster", "on", 4)

    assert {:error, {:unsupported_target, "actuator:toaster"}} =
             CommandExecutor.execute(delivery, state)
  end

  test "bare commands are rejected without a verified delivery receipt", %{state: state} do
    assert {:error, :missing_delivery_receipt} =
             CommandExecutor.execute(
               %{
                 "command_id" => "cmd-5",
                 "idempotency_key" => "idem-5",
                 "effect_key" => "effect-5",
                 "target" => "actuator:fan",
                 "requested_state" => "on"
               },
               state
             )
  end

  test "legacy command execution stores without manifests are migrated on startup" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-legacy-command-store-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    path = Path.join(dir, "commands.json")
    legacy_entries = %{
      "idem-legacy" => %{
        "command_id" => "cmd-legacy",
        "effect_key" => "effect-legacy",
        "target" => "actuator:fan",
        "requested_state" => "on",
        "adapter_attempt_id" => "adapter-legacy",
        "execution_status" => "io_accepted",
        "recorded_at" => "2026-05-10T12:00:00.000Z"
      }
    }

    File.write!(
      path,
      Contracts.canonical_json(%{
        "format_version" => "json-canonical-v1",
        "store_version" => 1,
        "entries" => legacy_entries
      }) <> "\n"
    )

    on_exit(fn -> File.rm_rf(dir) end)

    store_name =
      Module.concat(__MODULE__, "LegacyStore#{System.unique_integer([:positive])}")

    store =
      start_supervised!(
        {CommandExecutionStore, path: path, secret: "command-secret", name: store_name}
      )

    assert CommandExecutionStore.already_executed?(store, "idem-legacy")

    assert File.exists?("#{path}.manifest.json")
  end

  defp verified_delivery(
         command_id,
         idempotency_key,
         effect_key,
         target,
         requested_state,
         ordinal
       ) do
    secret = "command-secret"
    issued_at = "2026-05-10T12:00:00.000Z"
    expires_at = "2026-05-10T12:00:05.000Z"

    command_base = %{
      format_version: "json-canonical-v1",
      schema_id: "eigenforge.command_envelope",
      schema_version: 1,
      command_id: command_id,
      idempotency_key: idempotency_key,
      effect_key: effect_key,
      subject: "core_rule_stub",
      target: target,
      action: "command_actuator",
      scope: "room:placeholder",
      requested_state: requested_state,
      snapshot_id: "snapshot-#{ordinal}",
      snapshot_seq: ordinal,
      decision_event_id: "decision-#{ordinal}",
      reasoner_outcome_event_id: "reasoner-#{ordinal}",
      capability_event_id: "capability-#{ordinal}",
      policy_decision_id: "policy-#{ordinal}",
      issued_at: issued_at,
      expires_at: expires_at,
      payload_hash: "",
      signature_version: "hmac-sha256-v1",
      signature: ""
    }

    command =
      command_base
      |> Map.put(
        :payload_hash,
        Contracts.hash_excluding(command_base, [:payload_hash, :signature])
      )
      |> then(fn unsigned ->
        Map.put(
          unsigned,
          :signature,
          Contracts.sign_hmac_excluding(
            unsigned,
            secret,
            [:signature],
            "eigenforge:v1:command_envelope"
          )
        )
      end)
      |> CommandEnvelope.new!()
      |> wire_map()

    receipt_base = %{
      format_version: "json-canonical-v1",
      schema_id: "eigenforge.delivery_receipt",
      schema_version: 1,
      receipt_id: "receipt-#{ordinal}",
      command_id: command_id,
      decision_event_id: "decision-#{ordinal}",
      ledger_sequence: ordinal,
      ledger_event_hash: String.duplicate(Integer.to_string(ordinal), 64) |> String.slice(0, 64),
      delivered_topic: "commands:io",
      delivered_at: issued_at,
      signature_version: "hmac-sha256-v1",
      signature: ""
    }

    receipt =
      receipt_base
      |> Map.put(
        :signature,
        Contracts.sign_hmac_excluding(
          receipt_base,
          secret,
          [:signature],
          "eigenforge:v1:delivery_receipt"
        )
      )
      |> DeliveryReceipt.new!()
      |> wire_map()

    %{"command" => command, "receipt" => receipt}
  end

  defp wire_map(%_module{} = struct), do: struct |> Map.from_struct() |> wire_map()
  defp wire_map(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
