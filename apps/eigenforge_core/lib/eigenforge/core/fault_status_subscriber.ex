defmodule Eigenforge.Core.FaultStatusSubscriber do
  @moduledoc """
  Subscribes to IO fault/status events and selectively persists them.
  """

  use GenServer

  alias Eigenforge.Contracts
  alias Eigenforge.Core.AfterActionObserver
  alias Eigenforge.Core.LedgerProjections
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.TraceIdentity
  alias Eigenforge.Mailbox.Projections

  @default_server __MODULE__
  @default_registry Eigenforge.IO.FaultStatus.Registry

  @spec start_link(RuntimeConfig.t() | keyword()) :: GenServer.on_start()
  def start_link(%RuntimeConfig{} = config) do
    start_link(
      room_id: default_room_id(config),
      db_path: config.core_db_path,
      writer: LedgerWriter,
      mailbox_receipt_store: Eigenforge.Mailbox.ReceiptStore,
      after_action_observer: AfterActionObserver,
      io_fault_status_registry: @default_registry,
      snapshot_subscriber: Eigenforge.Core.SnapshotSubscriber,
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

  @impl true
  def init(opts) do
    state = %{
      room_id: Keyword.get(opts, :room_id),
      db_path: Keyword.get(opts, :db_path),
      writer: Keyword.get(opts, :writer, LedgerWriter),
      mailbox_receipt_store:
        Keyword.get(opts, :mailbox_receipt_store, Eigenforge.Mailbox.ReceiptStore),
      after_action_observer: Keyword.get(opts, :after_action_observer, AfterActionObserver),
      io_fault_status_registry: Keyword.get(opts, :io_fault_status_registry, @default_registry),
      snapshot_subscriber: Keyword.get(opts, :snapshot_subscriber, Eigenforge.Core.SnapshotSubscriber),
      seen_connection_transitions: MapSet.new()
    }

    case attempt_subscribe(state.io_fault_status_registry) do
      :ok -> {:ok, state}
      {:retry, delay_ms} ->
        Process.send_after(self(), :subscribe, delay_ms)
        {:ok, state}
    end
  end

  @impl true
  def handle_info(:subscribe, state) do
    case attempt_subscribe(state.io_fault_status_registry) do
      :ok -> {:noreply, state}
      {:retry, delay_ms} ->
        Process.send_after(self(), :subscribe, delay_ms)
        {:noreply, state}
    end
  end

  def handle_info({:io_fault_status, event}, state) do
    state =
      state
      |> maybe_persist_fault(event)
      |> maybe_resolve_pending_from_fault(event)

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp maybe_persist_fault(state, event) do
    if should_persist_fault?(event) and room_matches?(state, event) do
      if duplicate_connection_transition?(event, state) do
        state
      else
        case LedgerWriter.append(state.writer, fault_ledger_attrs(event)) do
          {:ok, _event} -> remember_connection_transition(event, state)
          {:error, _reason} -> state
        end
      end
    else
      state
    end
  end

  defp maybe_resolve_pending_from_fault(state, event) do
    if room_matches?(state, event) do
      with {:ok, pending} <- build_pending_entry(state),
           {:ok, after_action} <-
             state.after_action_observer.interpret_fault(
               pending.command,
               fault_resolution_context(event),
               pending.pre_command_snapshot
             ),
           :ok <- append_after_action(state.writer, after_action, pending.refs) do
        _ =
          GenServer.call(
            state.snapshot_subscriber,
            {:fault_status_pending_command_resolved, pending.command.command_id},
            5_000
          )
      end
    end

    state
  end

  defp room_matches?(%{room_id: nil}, _event), do: true
  defp room_matches?(%{room_id: room_id}, event), do: room_id == event.room_id

  defp should_persist_fault?(event) do
    MapSet.member?(connection_fault_types(), event.fault_type) or
      Map.get(event.metadata || %{}, "ooda_relevant", false) or
      Map.get(event.metadata || %{}, "audit", false)
  end

  defp duplicate_connection_transition?(event, state) do
    case connection_transition_key(event) do
      nil -> false
      key -> MapSet.member?(state.seen_connection_transitions, key)
    end
  end

  defp fault_ledger_attrs(event) do
    %{
      event_type: ledger_event_type(event.fault_type),
      subject: "io_adapter",
      source_app: "eigenforge_core",
      payload: Contracts.signable_map(event)
    }
  end

  defp append_after_action(writer, after_action, refs) do
    %{
      event_type: "after_action_recorded",
      event_id: refs.after_action_event_id,
      subject: "core_rule_stub",
      source_app: "eigenforge_core",
      consensus_decision_id: refs.consensus_decision_id,
      consensus_status: "single_core_finalized",
      correlation_id: refs.correlation_id,
      payload: Contracts.signable_map(after_action)
    }
    |> then(&LedgerWriter.append(writer, &1))
  end

  defp ledger_event_type(fault_type) do
    if MapSet.member?(connection_fault_types(), fault_type),
      do: "connection_status_observed",
      else: "io_fault_observed"
  end

  defp remember_connection_transition(event, state) do
    case connection_transition_key(event) do
      nil -> state
      key -> %{state | seen_connection_transitions: MapSet.put(state.seen_connection_transitions, key)}
    end
  end

  defp connection_transition_key(event) do
    if MapSet.member?(connection_fault_types(), event.fault_type) do
      correlation_id = get_in(event.metadata || %{}, ["correlation_id"])
      if blank?(correlation_id), do: nil, else: {event.fault_type, correlation_id}
    end
  end

  defp connection_fault_types do
    MapSet.new(["connection_up", "connection_down", "reconnecting", "degraded", "recovered"])
  end

  defp build_pending_entry(state) do
    with {:ok, room_state} <- fetch_room_state(state),
         pending_command_id when pending_command_id not in [nil, ""] <-
           room_state["pending_command_id"],
         {:ok, command} <- fetch_command(pending_command_id, state.db_path) do
      {:ok,
       %{
         command: command,
         pre_command_snapshot: pre_command_snapshot(room_state, command),
         refs: event_refs_from_command(command)
       }}
    end
  end

  defp fetch_room_state(%{db_path: db_path, room_id: room_id}) do
    sql = """
    SELECT *
    FROM latest_room_control_state
    WHERE room_id = ?1
    LIMIT 1;
    """

    case LedgerProjections.query_json(db_path, sql, [room_id]) do
      {:ok, [row]} -> {:ok, row}
      {:ok, []} -> {:error, :missing_room_state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_command(command_id, db_path) do
    sql = """
    SELECT payload
    FROM ledger_events
    WHERE event_type = 'command_envelope_issued'
      AND json_extract(payload, '$.command_id') = ?1
    ORDER BY sequence DESC
    LIMIT 1;
    """

    try do
      case LedgerProjections.query_json(db_path, sql, [command_id]) do
        {:ok, [%{"payload" => payload_json}]} ->
          payload_json
          |> Contracts.decode_json!()
          |> then(&{:ok, Eigenforge.Contracts.CommandEnvelope.new!(&1)})

        {:ok, []} ->
          {:error, :missing_pending_command}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error -> {:error, {:invalid_pending_command, Exception.message(error)}}
    end
  end

  defp event_refs_from_command(command) do
    refs = TraceIdentity.stable_id("event", ["after_action_recorded", command.snapshot_id])

    %{
      after_action_event_id: refs,
      consensus_decision_id: TraceIdentity.stable_id("consensus", [command.snapshot_id]),
      correlation_id: TraceIdentity.stable_id("correlation", [command.snapshot_id])
    }
  end

  defp pre_command_snapshot(room_state, command) do
    %{
      "snapshot_id" => room_state["latest_snapshot_id"] || command.snapshot_id,
      "snapshot_seq" => command.snapshot_seq,
      "snapshot_hash" => room_state["latest_snapshot_hash"] || command.payload_hash,
      "room_id" => room_state["room_id"] || room_id_from_scope(command.scope),
      "co2_ppm" => room_state["co2_ppm"],
      "humidity_basis_points" => room_state["humidity_basis_points"],
      "temperature_millicelsius" => room_state["temperature_millicelsius"],
      "fan_state" => room_state["fan_state"],
      "source_entity_ids" => %{},
      "source_observation_ids" => %{},
      "source_observed_at" => %{},
      "source_received_seq" => %{
        "fan" => room_state["source_received_seq_fan"] || command.snapshot_seq
      },
      "source_received_monotonic_ms" => %{"fan" => room_state["source_received_monotonic_ms_fan"]},
      "source_status" => %{},
      "normalized_at" => room_state["updated_at"] || command.issued_at,
      "freshness" => room_state["freshness"] || "fresh"
    }
  end

  defp fault_resolution_context(event) do
    %{
      fault_type: event.fault_type,
      event_id: event.event_id,
      source_received_seq: get_in(event.metadata || %{}, ["source_received_seq"]),
      source_received_monotonic_ms: get_in(event.metadata || %{}, ["source_received_monotonic_ms"]),
      reported_at: event.observed_at
    }
  end

  defp room_id_from_scope("room:" <> room_id), do: room_id
  defp room_id_from_scope(_scope), do: "placeholder"

  defp default_room_id(config) do
    case Eigenforge.Core.SignedConfig.load_device_inventory(config) do
      {:ok, %{active_room: %{"room_id" => room_id}}} -> room_id
      _ -> nil
    end
  end

  defp blank?(value), do: value in [nil, ""]

  defp attempt_subscribe(registry_name) do
    try do
      case Eigenforge.IO.FaultStatus.subscribe(registry_name) do
        {:ok, _} -> :ok
        {:error, {:already_registered, _}} -> :ok
        {:error, {:noproc, _}} -> {:retry, 100}
        {:error, _reason} -> {:retry, 250}
      end
    rescue
      ArgumentError -> {:retry, 100}
    end
  end
end
