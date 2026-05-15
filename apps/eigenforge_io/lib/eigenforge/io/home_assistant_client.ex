defmodule Eigenforge.IO.HomeAssistantClient do
  @moduledoc """
  Testable V1 Home Assistant client supervision slice.

  The transport is injected so runtime tests can cover degraded startup,
  reconnect backoff, entity validation, snapshot publication, and command
  dispatch without requiring a live Home Assistant instance.
  """

  use GenServer

  alias Eigenforge.Core.PubSub
  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.SignedConfig
  alias Eigenforge.IO.CommandExecutor
  alias Eigenforge.IO.FaultStatus
  alias Eigenforge.Mailbox.ChannelManager
  alias Eigenforge.IO.HomeAssistantAdapter

  @default_server __MODULE__
  @commands_topic "commands:io"

  @spec start_link(RuntimeConfig.t() | keyword()) :: GenServer.on_start()
  def start_link(%RuntimeConfig{} = config) do
    start_link(
      room_id: active_room_id(config),
      home_assistant: config.home_assistant,
      hmac_secret: config.hmac_secret,
      ha_reconnect_max_ms: config.ha_reconnect_max_ms,
      io_fault_status: FaultStatus,
      pubsub_registry: Eigenforge.Core.PubSub.Registry,
      mailbox_registry: Eigenforge.Mailbox.Registry,
      mailbox_receipt_store: Eigenforge.Mailbox.ReceiptStore,
      command_execution_store: Eigenforge.IO.CommandExecutionStore,
      transport: Eigenforge.IO.HomeAssistantTransport.Live,
      name: @default_server
    )
  end

  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name, @default_server)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      _ -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @spec child_spec(RuntimeConfig.t() | keyword()) :: Supervisor.child_spec()
  def child_spec(%RuntimeConfig{} = config) do
    %{id: @default_server, start: {__MODULE__, :start_link, [config]}}
  end

  def child_spec(opts) when is_list(opts) do
    %{id: Keyword.get(opts, :name, @default_server), start: {__MODULE__, :start_link, [opts]}}
  end

  @spec ingest(GenServer.server(), map(), keyword()) :: :ok | {:error, term()}
  def ingest(server \\ @default_server, raw_states, opts \\ []) when is_map(raw_states) do
    GenServer.call(server, {:ingest, raw_states, opts})
  end

  @impl true
  def init(opts) do
    home_assistant = Keyword.fetch!(opts, :home_assistant)
    mailbox_registry = Keyword.get(opts, :mailbox_registry, Eigenforge.Mailbox.Registry)
    {:ok, _} = ChannelManager.subscribe(@commands_topic, registry_name: mailbox_registry)

    state = %{
      room_id: Keyword.fetch!(opts, :room_id),
      home_assistant: home_assistant,
      hmac_secret: Keyword.fetch!(opts, :hmac_secret),
      ha_reconnect_max_ms: Keyword.fetch!(opts, :ha_reconnect_max_ms),
      io_fault_status: Keyword.get(opts, :io_fault_status, FaultStatus),
      pubsub_registry: Keyword.get(opts, :pubsub_registry, Eigenforge.Core.PubSub.Registry),
      mailbox_registry: mailbox_registry,
      mailbox_receipt_store:
        Keyword.get(opts, :mailbox_receipt_store, Eigenforge.Mailbox.ReceiptStore),
      command_execution_store:
        Keyword.get(opts, :command_execution_store, Eigenforge.IO.CommandExecutionStore),
      transport: Keyword.get(opts, :transport, __MODULE__.Transport.Noop),
      command_observer: Keyword.get(opts, :command_observer),
      utc_now: Keyword.get(opts, :utc_now, &DateTime.utc_now/0),
      monotonic_now_ms:
        Keyword.get(opts, :monotonic_now_ms, fn -> System.monotonic_time(:millisecond) end),
      connected?: false,
      physical_control_enabled?: false,
      conn: nil,
      reconnect_attempt: 0,
      last_snapshot_seq: 0
    }

    state =
      state
      |> Map.put(:started_at_utc, current_utc(state))
      |> Map.put(:started_monotonic_ms, current_monotonic_ms(state))

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_call({:ingest, raw_states, opts}, _from, state) do
    reply =
      case publish_snapshot(raw_states, opts, state) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_transport(state) do
      {:ok, conn, initial_states} ->
        next_state = %{state | conn: conn, connected?: true}

        case HomeAssistantAdapter.dynamic_validate_entities(
               initial_states,
               state.home_assistant.entity_ids
             ) do
          :ok ->
            case publish_snapshot(
                   initial_states,
                   [
                     snapshot_seq: next_state.last_snapshot_seq + 1,
                     normalized_at: timestamp(state)
                   ],
                   next_state
                 ) do
              :ok ->
                _ = record_status(next_state, "connection_up", correlation_id: "ha-connect")

                {:noreply,
                 %{
                   next_state
                   | physical_control_enabled?: true,
                     reconnect_attempt: 0,
                     last_snapshot_seq: next_state.last_snapshot_seq + 1
                 }}

              {:error, reason} ->
                _ =
                  record_status(state, "degraded",
                    message: inspect(reason),
                    correlation_id: "ha-connect"
                  )

                {:noreply, %{next_state | physical_control_enabled?: false}}
            end

          {:error, errors} ->
            _ =
              record_status(state, "degraded",
                message: inspect(errors),
                correlation_id: "ha-connect"
              )

            {:noreply, %{next_state | physical_control_enabled?: false}}
        end

      {:error, reason} ->
        _ =
          record_status(state, "connection_down",
            message: inspect(reason),
            correlation_id: "ha-connect"
          )

        _ =
          record_status(state, "reconnecting",
            message: inspect(reason),
            correlation_id: "ha-reconnect-#{state.reconnect_attempt + 1}"
          )

        delay =
          HomeAssistantAdapter.next_backoff_ms(state.reconnect_attempt, state.ha_reconnect_max_ms)

        Process.send_after(self(), :connect, delay)

        {:noreply,
         %{
           state
           | reconnect_attempt: state.reconnect_attempt + 1,
             connected?: false,
             physical_control_enabled?: false,
             conn: nil
         }}
    end
  end

  def handle_info({:home_assistant_transport_snapshot, conn, raw_states}, state)
      when is_map(raw_states) do
    next_state =
      if state.connected? and state.conn == conn do
        case publish_snapshot(
               raw_states,
               [
                 snapshot_seq: state.last_snapshot_seq + 1,
                 normalized_at: timestamp(state)
               ],
               state
             ) do
          :ok ->
            %{state | last_snapshot_seq: state.last_snapshot_seq + 1}

          {:error, _reason} ->
            state
        end
      else
        state
      end

    {:noreply, next_state}
  end

  def handle_info({:home_assistant_transport_closed, conn, reason}, state) do
    next_state =
      if state.conn == conn or state.connected? do
        _ =
          record_status(state, "connection_down",
            message: inspect(reason),
            correlation_id: "ha-connect"
          )

        _ =
          record_status(state, "reconnecting",
            message: inspect(reason),
            correlation_id: "ha-reconnect-#{state.reconnect_attempt + 1}"
          )

        delay =
          HomeAssistantAdapter.next_backoff_ms(state.reconnect_attempt, state.ha_reconnect_max_ms)

        Process.send_after(self(), :connect, delay)

        %{
          state
          | reconnect_attempt: state.reconnect_attempt + 1,
            connected?: false,
            physical_control_enabled?: false,
            conn: nil
        }
      else
        state
      end

    {:noreply, next_state}
  end

  def handle_info({:mailbox_command, @commands_topic, delivery}, state) when is_map(delivery) do
    next_state =
      case CommandExecutor.execute(delivery, state) do
        {:ok, _result} ->
          state

        {:error, reason} ->
          command = delivery["command"] || %{}
          fault_type = fault_type_for_reason(reason)
          _ = record_fault(state, fault_type, reason, command)
          state
      end

    {:noreply, next_state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp connect_transport(state) do
    if function_exported?(state.transport, :connect, 3) do
      state.transport.connect(state.home_assistant.url, state.home_assistant.token,
        entity_ids: state.home_assistant.entity_ids
      )
    else
      state.transport.connect(state.home_assistant.url, state.home_assistant.token)
    end
  end

  defp publish_snapshot(raw_states, opts, state) do
    opts_map = Map.new(opts)

    normalize_opts = [
      room_id: state.room_id,
      snapshot_id: Map.get(opts_map, :snapshot_id, "ha-snapshot-#{state.last_snapshot_seq + 1}"),
      snapshot_seq: Map.get(opts_map, :snapshot_seq, state.last_snapshot_seq + 1),
      normalized_at: Map.get(opts_map, :normalized_at, timestamp(state))
    ]

    case HomeAssistantAdapter.normalize_snapshot(
           state.home_assistant.entity_ids,
           raw_states,
           normalize_opts
         ) do
      {:ok, snapshot} ->
        PubSub.publish("io_state:room:#{state.room_id}", snapshot,
          registry_name: state.pubsub_registry
        )

        :ok

      {:error, reason} ->
        _ = record_fault(state, "malformed_observation", reason, %{})
        {:error, reason}
    end
  end

  defp record_status(state, fault_type, attrs) do
    FaultStatus.record(state.io_fault_status, %{
      source: "home_assistant",
      room_id: state.room_id,
      fault_type: fault_type,
      message: Keyword.get(attrs, :message),
      correlation_id: Keyword.get(attrs, :correlation_id),
      metadata: %{}
    })
  end

  defp record_fault(state, fault_type, reason, command) do
    FaultStatus.record(state.io_fault_status, %{
      source: "home_assistant",
      room_id: state.room_id,
      fault_type: fault_type,
      message: inspect(reason),
      audit: true,
      source_received_seq: state.last_snapshot_seq + 1,
      source_received_monotonic_ms: current_monotonic_ms(state),
      metadata: %{
        "command_id" => command["command_id"],
        "target" => command["target"]
      }
    })
  end

  defp fault_type_for_reason(:command_expired), do: "command_expired"
  defp fault_type_for_reason(:duplicate_idempotency_key), do: "duplicate_idempotency_key"
  defp fault_type_for_reason(:invalid_command_signature), do: "invalid_command_signature"

  defp fault_type_for_reason(:invalid_delivery_receipt_signature),
    do: "invalid_delivery_receipt_signature"

  defp fault_type_for_reason(:receipt_command_mismatch), do: "receipt_command_mismatch"
  defp fault_type_for_reason(:receipt_decision_mismatch), do: "receipt_decision_mismatch"

  defp fault_type_for_reason(:missing_committed_ledger_reference),
    do: "missing_committed_ledger_reference"

  defp fault_type_for_reason(:not_connected), do: "not_connected"
  defp fault_type_for_reason(:physical_control_disabled), do: "physical_control_disabled"
  defp fault_type_for_reason({:unsupported_target, target}), do: "unsupported_target:#{target}"
  defp fault_type_for_reason(:invalid_command), do: "invalid_command"
  defp fault_type_for_reason(_reason), do: "adapter_execution_failed"

  defp active_room_id(config) do
    case SignedConfig.load_device_inventory(config) do
      {:ok, %{active_room: %{"room_id" => room_id}}} -> room_id
      _ -> "placeholder"
    end
  end

  defp timestamp(state) do
    state
    |> current_utc()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp current_utc(state), do: state.utc_now.()
  defp current_monotonic_ms(state), do: state.monotonic_now_ms.()

  defmodule Transport do
    @callback connect(String.t(), String.t()) :: {:ok, term(), map()} | {:error, term()}
    @callback connect(String.t(), String.t(), keyword()) ::
                {:ok, term(), map()} | {:error, term()}
    @callback command(term(), map()) :: {:ok, term()} | {:error, term()}

    defmodule Noop do
      @behaviour Eigenforge.IO.HomeAssistantClient.Transport

      @impl true
      def connect(_url, _token), do: {:error, :not_implemented}

      @impl true
      def connect(url, token, _opts), do: connect(url, token)

      @impl true
      def command(_conn, _request), do: {:error, :not_implemented}
    end
  end
end
