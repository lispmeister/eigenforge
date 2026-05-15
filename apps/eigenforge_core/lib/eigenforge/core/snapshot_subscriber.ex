defmodule Eigenforge.Core.SnapshotSubscriber do
  @moduledoc """
  Supervised OODA pipeline entrypoint for normalized snapshots.
  """

  use GenServer

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Core.ActuatorGate
  alias Eigenforge.Core.AfterActionObserver
  alias Eigenforge.Core.CapabilityChecker
  alias Eigenforge.Core.CommandIssuer
  alias Eigenforge.Core.LedgerProjections
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.PolicyEngine
  alias Eigenforge.Core.PendingCommandRecovery
  alias Eigenforge.Core.PubSub
  alias Eigenforge.Core.Reasoners.Co2Rules
  alias Eigenforge.Core.TraceIdentity
  alias Eigenforge.Mailbox.CommandPublisher

  @default_server __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name, @default_server)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      _ -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, @default_server),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)

    state = %{
      room_id: room_id,
      mailbox_registry: Keyword.get(opts, :mailbox_registry, Eigenforge.Mailbox.Registry),
      mailbox_receipt_store:
        Keyword.get(opts, :mailbox_receipt_store, Eigenforge.Mailbox.ReceiptStore),
      writer: Keyword.get(opts, :writer, LedgerWriter),
      db_path: Keyword.get(opts, :db_path),
      io_mode: Keyword.get(opts, :io_mode, "simulator"),
      after_action_timeout_ms: Keyword.get(opts, :after_action_timeout_ms, 3_000),
      reasoner_module: Keyword.get(opts, :reasoner_module, Co2Rules),
      after_action_observer: Keyword.get(opts, :after_action_observer, AfterActionObserver),
      utc_now: Keyword.get(opts, :utc_now, &DateTime.utc_now/0),
      monotonic_now_ms:
        Keyword.get(opts, :monotonic_now_ms, fn -> System.monotonic_time(:millisecond) end),
      core_node_id: Keyword.get(opts, :core_node_id, "core_a"),
      secret: Keyword.fetch!(opts, :secret),
      processed_snapshot_ids: MapSet.new(),
      pending_commands: %{}
    }

    state =
      state
      |> Map.put(:started_at_utc, current_utc(state))
      |> Map.put(:started_monotonic_ms, current_monotonic_ms(state))

    state = PendingCommandRecovery.recover_pending_commands(state)

    pubsub_registry = Keyword.get(opts, :pubsub_registry, Eigenforge.Core.PubSub.Registry)
    :ok = subscribe(room_id, pubsub_registry)

    io_fault_status_registry =
      Keyword.get(opts, :io_fault_status_registry, Eigenforge.Core.IoFaultStatus.Registry)

    :ok = subscribe_faults(io_fault_status_registry)

    {:ok, state}
  end

  @impl true
  def handle_info({:core_pubsub, topic, snapshot_payload}, state) do
    state =
      if topic == room_topic(state.room_id) do
        case normalize_snapshot(snapshot_payload) do
          {:ok, snapshot} ->
            _ = maybe_observe_snapshot(snapshot, state)
            state = maybe_resolve_pending_from_snapshot(snapshot, state)

            if MapSet.member?(state.processed_snapshot_ids, snapshot.snapshot_id) do
              state
            else
              case run_pipeline(snapshot, state) do
                {:ok, next_state} ->
                  %{
                    next_state
                    | processed_snapshot_ids:
                        MapSet.put(next_state.processed_snapshot_ids, snapshot.snapshot_id)
                  }

                _ ->
                  state
              end
            end

          {:error, _reason} ->
            state
        end
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:io_fault_status, event}, state) do
    {:noreply, maybe_resolve_pending_from_fault(event, state)}
  end

  def handle_info({:after_action_timeout, command_id}, state) do
    {:noreply, maybe_timeout_pending_command(command_id, state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run_pipeline(snapshot, state) do
    refs = event_refs(snapshot)

    with {:ok, reasoner} <- state.reasoner_module.reason(snapshot),
         {:ok, gated_reasoner} <- ActuatorGate.gate(reasoner, snapshot),
         {:ok, capability} <- CapabilityChecker.check(gated_reasoner, snapshot),
         {:ok, policy} <- PolicyEngine.decide(gated_reasoner, capability, snapshot),
         {:ok, command} <-
           CommandIssuer.issue(gated_reasoner, capability, policy, snapshot, state.secret,
             core_node_id: state.core_node_id,
             consensus_decision_id: refs.consensus_decision_id,
             decision_event_id: refs.command_event_id,
             reasoner_outcome_event_id: refs.reasoner_event_id,
             capability_event_id: refs.capability_event_id,
             effect_epoch: resolved_effect_epoch(snapshot, state)
           ),
         {:ok, guarded_command} <- apply_in_flight_guard(command, snapshot.room_id, state),
         payloads <-
           [gated_reasoner, capability, policy, guarded_command] |> Enum.reject(&is_nil/1),
         {:ok, appended_events} <- append_payloads(payloads, snapshot, refs, state) do
      if guarded_command do
        command_event = Map.fetch!(appended_events, "command_envelope_issued")
        next_state = register_pending_command(guarded_command, snapshot, refs, state)

        _ =
          CommandPublisher.publish("commands:io", guarded_command,
            registry_name: state.mailbox_registry,
            receipt_store: state.mailbox_receipt_store,
            ledger_sequence: command_event.sequence,
            ledger_event_hash: command_event.event_hash,
            decision_event_id: command_event.event_id
          )

        {:ok, next_state}
      else
        {:ok, state}
      end
    end
  end

  defp apply_in_flight_guard(nil, _room_id, _state), do: {:ok, nil}

  defp apply_in_flight_guard(command, _room_id, %{db_path: nil}), do: {:ok, command}

  defp apply_in_flight_guard(command, room_id, state) do
    if in_flight_effect?(state.db_path, room_id, command.effect_key) do
      {:ok, nil}
    else
      {:ok, command}
    end
  end

  defp in_flight_effect?(db_path, room_id, effect_key) do
    sql = """
    SELECT pending_effect_key
    FROM latest_room_control_state
    WHERE room_id = '#{String.replace(room_id, "'", "''")}'
    LIMIT 1;
    """

    case LedgerProjections.query_json(db_path, sql) do
      {:ok, [%{"pending_effect_key" => pending_effect_key}]} -> pending_effect_key == effect_key
      _ -> false
    end
  end

  defp append_payloads(payloads, _snapshot, refs, state) do
    Enum.reduce_while(payloads, {:ok, %{}}, fn payload, {:ok, acc} ->
      event_type = event_type(payload)

      attrs = %{
        event_id: event_id_for(event_type, refs),
        event_type: event_type,
        payload: payload,
        subject: "core_rule_stub",
        source_app: "eigenforge_core",
        consensus_decision_id: refs.consensus_decision_id,
        consensus_status: "single_core_finalized",
        correlation_id: refs.correlation_id
      }

      case LedgerWriter.append(state.writer, attrs) do
        {:ok, event} ->
          acc = Map.put(acc, event_type, event)

          case append_stale_deny(payload, refs, state) do
            {:ok, nil} ->
              {:cont, {:ok, acc}}

            {:ok, stale_event} ->
              {:cont, {:ok, Map.put(acc, "stale_snapshot_denied", stale_event)}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp append_stale_deny(
         %Eigenforge.Contracts.PolicyDecision{decision: "deny_stale_snapshot"} = policy,
         refs,
         state
       ) do
    attrs = %{
      event_id: refs.stale_deny_event_id,
      event_type: "stale_snapshot_denied",
      payload: policy,
      subject: "core_rule_stub",
      source_app: "eigenforge_core",
      consensus_decision_id: refs.consensus_decision_id,
      consensus_status: "single_core_finalized",
      correlation_id: refs.correlation_id
    }

    LedgerWriter.append(state.writer, attrs)
  end

  defp append_stale_deny(_payload, _refs, _state), do: {:ok, nil}

  defp normalize_snapshot(%NormalizedSnapshot{} = snapshot), do: {:ok, snapshot}

  defp normalize_snapshot(snapshot) when is_map(snapshot) do
    {:ok, NormalizedSnapshot.new!(snapshot)}
  rescue
    error -> {:error, {:invalid_snapshot, Exception.message(error)}}
  end

  defp maybe_observe_snapshot(_snapshot, %{db_path: nil}), do: :ok

  defp maybe_observe_snapshot(snapshot, state) do
    LedgerProjections.observe_snapshot(state.db_path, snapshot, io_mode: state.io_mode)
  end

  defp maybe_resolve_pending_from_snapshot(snapshot, state) do
    Enum.reduce(state.pending_commands, state, fn {command_id, pending}, acc ->
      if pending.command.target == "actuator:fan" and post_delivery_snapshot?(snapshot, pending) do
        case acc.after_action_observer.interpret_observation(
               pending.command,
               pending.pre_command_snapshot,
               %{
                 observed_state: snapshot.fan_state,
                 source_observation_id:
                   get_in(snapshot.source_observation_ids, ["fan"]) ||
                     get_in(snapshot.source_observation_ids, [:fan]),
                 source_received_seq:
                   get_in(snapshot.source_received_seq, ["fan"]) ||
                     get_in(snapshot.source_received_seq, [:fan]),
                 source_received_monotonic_ms:
                   get_in(snapshot.source_received_monotonic_ms, ["fan"]) ||
                     get_in(snapshot.source_received_monotonic_ms, [:fan]),
                 reported_at: snapshot.normalized_at
               }
             ) do
          {:ok, after_action} ->
            refs = pending.refs

            case append_payloads([after_action], snapshot, refs, acc) do
              {:ok, _appended_events} -> drop_pending_command(acc, command_id)
              {:error, _reason} -> acc
            end

          {:error, _reason} ->
            acc
        end
      else
        acc
      end
    end)
  end

  defp maybe_resolve_pending_from_fault(event, state) do
    Enum.reduce(state.pending_commands, state, fn {command_id, pending}, acc ->
      if event.room_id == acc.room_id do
        case acc.after_action_observer.interpret_fault(
               pending.command,
               %{
                 fault_type: event.fault_type,
                 event_id: event.event_id,
                 source_received_seq: get_in(event.metadata || %{}, ["source_received_seq"]),
                 source_received_monotonic_ms:
                   get_in(event.metadata || %{}, ["source_received_monotonic_ms"]),
                 reported_at: event.observed_at
               },
               pending.pre_command_snapshot
             ) do
          {:ok, after_action} ->
            refs = pending.refs
            synthetic_snapshot = pending.pre_command_snapshot

            case append_payloads([after_action], synthetic_snapshot, refs, acc) do
              {:ok, _appended_events} -> drop_pending_command(acc, command_id)
              {:error, _reason} -> acc
            end

          {:error, _reason} ->
            acc
        end
      else
        acc
      end
    end)
  end

  defp register_pending_command(command, snapshot, refs, state) do
    timer_ref =
      Process.send_after(
        self(),
        {:after_action_timeout, command.command_id},
        timeout_ms_for_pending(command, state.after_action_timeout_ms, state)
      )

    pending = %{
      command: command,
      pre_command_snapshot: Contracts.signable_map(snapshot),
      refs: refs,
      timer_ref: timer_ref
    }

    %{state | pending_commands: Map.put(state.pending_commands, command.command_id, pending)}
  end

  defp drop_pending_command(state, command_id) do
    case Map.get(state.pending_commands, command_id) do
      %{timer_ref: timer_ref} when is_reference(timer_ref) -> Process.cancel_timer(timer_ref)
      _ -> :ok
    end

    %{state | pending_commands: Map.delete(state.pending_commands, command_id)}
  end

  defp post_delivery_snapshot?(snapshot, pending) do
    current_seq =
      get_in(snapshot.source_received_seq, ["fan"]) ||
        get_in(snapshot.source_received_seq, [:fan])

    pending_seq =
      pending.pre_command_snapshot
      |> Map.get("source_received_seq", %{})
      |> Map.get("fan")

    current_ms =
      get_in(snapshot.source_received_monotonic_ms, ["fan"]) ||
        get_in(snapshot.source_received_monotonic_ms, [:fan])

    pending_ms =
      pending.pre_command_snapshot
      |> Map.get("source_received_monotonic_ms", %{})
      |> Map.get("fan")

    (is_integer(current_seq) and is_integer(pending_seq) and current_seq > pending_seq) or
      (is_integer(current_ms) and is_integer(pending_ms) and current_ms > pending_ms)
  end

  defp maybe_timeout_pending_command(command_id, state) do
    case Map.get(state.pending_commands, command_id) do
      nil ->
        state

      pending ->
        case state.after_action_observer.timeout(
               pending.command,
               reported_at: pending.command.expires_at
             ) do
          {:ok, after_action} ->
            case append_payloads(
                   [after_action],
                   pending.pre_command_snapshot,
                   pending.refs,
                   state
                 ) do
              {:ok, _appended_events} -> drop_pending_command(state, command_id)
              {:error, _reason} -> state
            end

          {:error, _reason} ->
            state
        end
    end
  end

  def recover_pending_commands(%{db_path: nil} = state), do: state

  def recover_pending_commands(state) do
    case fetch_all_pending_room_states(state) do
      {:ok, room_states} ->
        Enum.reduce(room_states, state, fn room_state, acc ->
          case build_pending_entry(room_state, acc) do
            {:ok, pending} ->
              timeout_ms = recovered_timeout_ms(pending, acc)

              if expired?(pending.command.expires_at, acc) or timeout_ms == 0 do
                maybe_record_recovery_timeout(acc, pending)
              else
                register_recovered_pending_command(acc, pending, timeout_ms)
              end

            {:error, _reason} ->
              acc
          end
        end)

      {:error, _reason} ->
        state
    end
  end

  defp fetch_all_pending_room_states(%{db_path: db_path, room_id: room_id}) do
    sql = """
    SELECT *
    FROM latest_room_control_state
    WHERE room_id = '#{String.replace(room_id, "'", "''")}'
      AND pending_command_id IS NOT NULL
      AND pending_command_id != '';
    """

    case LedgerProjections.query_json(db_path, sql) do
      {:ok, rows} -> {:ok, rows}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_pending_entry(room_state, state) do
    command_id = room_state["pending_command_id"]

    with {:ok, command} <- fetch_command(command_id, state.db_path),
         {:ok, receipts} <-
           Eigenforge.Mailbox.ReceiptStore.entries_for_command(
             state.mailbox_receipt_store,
             command.command_id
           ) do
      {:ok,
       %{
         command: command,
         pre_command_snapshot: pre_command_snapshot(room_state, command),
         refs: event_refs_from_command(command),
         receipt_entry: latest_receipt_entry(receipts)
       }}
    end
  end

  defp fetch_room_state(%{db_path: db_path, room_id: room_id}) do
    sql = """
    SELECT *
    FROM latest_room_control_state
    WHERE room_id = '#{String.replace(room_id, "'", "''")}'
    LIMIT 1;
    """

    case LedgerProjections.query_json(db_path, sql) do
      {:ok, [row]} -> {:ok, row}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_command(command_id, db_path) do
    sql = """
    SELECT payload
    FROM ledger_events
    WHERE event_type = 'command_envelope_issued'
      AND json_extract(payload, '$.command_id') = '#{String.replace(command_id, "'", "''")}'
    ORDER BY sequence DESC
    LIMIT 1;
    """

    try do
      case LedgerProjections.query_json(db_path, sql) do
        {:ok, [%{"payload" => payload_json}]} ->
          payload_json
          |> Contracts.decode_json!()
          |> then(&{:ok, CommandEnvelope.new!(&1)})

        {:ok, []} ->
          {:error, :missing_pending_command}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error -> {:error, {:invalid_pending_command, Exception.message(error)}}
    end
  end

  defp register_recovered_pending_command(state, pending, timeout_ms) do
    timer_ref =
      Process.send_after(
        self(),
        {:after_action_timeout, pending.command.command_id},
        timeout_ms
      )

    pending = Map.put(pending, :timer_ref, timer_ref)

    %{
      state
      | pending_commands: Map.put(state.pending_commands, pending.command.command_id, pending)
    }
  end

  defp maybe_record_recovery_timeout(state, pending) do
    case state.after_action_observer.timeout(
           pending.command,
           reported_at: pending.command.expires_at
         ) do
      {:ok, after_action} ->
        case append_payloads([after_action], pending.pre_command_snapshot, pending.refs, state) do
          {:ok, _appended_events} -> state
          {:error, _reason} -> state
        end

      {:error, _reason} ->
        state
    end
  end

  defp recovered_timeout_ms(pending, %{after_action_timeout_ms: default_timeout_ms} = state) do
    pending.receipt_entry
    |> timeout_deadline(default_timeout_ms, pending.command.expires_at)
    |> case do
      %DateTime{} = deadline ->
        remaining_ms = remaining_until(deadline, state)
        max(0, remaining_ms)

      nil ->
        0
    end
  end

  defp timeout_deadline(nil, _default_timeout_ms, expires_at), do: parse_timestamp(expires_at)

  defp timeout_deadline(receipt_entry, default_timeout_ms, expires_at) do
    metadata = receipt_entry["phase_metadata"] || %{}
    receipt = receipt_entry["receipt"] || %{}
    phase = receipt_entry["delivery_phase"]

    base_timestamp =
      metadata["accepted_at"] ||
        metadata["published_at"] ||
        metadata["receipt_stored_at"] ||
        receipt["delivered_at"]

    cond do
      phase == "io_accepted" ->
        with %DateTime{} = parsed_base <- parse_timestamp(base_timestamp) do
          DateTime.add(parsed_base, default_timeout_ms, :millisecond)
        else
          _ -> parse_timestamp(expires_at)
        end

      true ->
        parse_timestamp(expires_at)
    end
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

  defp resolved_effect_epoch(snapshot, %{db_path: nil}) do
    effect_epoch(snapshot)
  end

  defp resolved_effect_epoch(snapshot, state) do
    case Map.get(snapshot.source_observation_ids, "fan") ||
           Map.get(snapshot.source_observation_ids, :fan) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        case fetch_room_state(state) do
          {:ok, room_state} ->
            room_state["latest_after_action_id"] || "startup"

          _ ->
            "startup"
        end
    end
  end

  defp effect_epoch(snapshot) do
    case Map.get(snapshot.source_observation_ids, "fan") ||
           Map.get(snapshot.source_observation_ids, :fan) do
      value when is_binary(value) and value != "" -> value
      _ -> "startup"
    end
  end

  defp event_refs_from_command(command) do
    refs = event_refs(%{snapshot_id: command.snapshot_id})

    %{refs | command_event_id: command.decision_event_id}
  end

  defp latest_receipt_entry([]), do: nil

  defp latest_receipt_entry(entries) do
    Enum.reduce(entries, nil, fn entry, current_best ->
      case current_best do
        nil ->
          entry

        best_entry ->
          if DateTime.compare(
               latest_receipt_timestamp(entry),
               latest_receipt_timestamp(best_entry)
             ) == :gt do
            entry
          else
            best_entry
          end
      end
    end)
  end

  defp latest_receipt_timestamp(entry) do
    entry
    |> timeout_metadata_timestamp()
    |> parse_timestamp()
    |> case do
      %DateTime{} = parsed -> parsed
      nil -> ~U[1970-01-01 00:00:00Z]
    end
  end

  defp room_id_from_scope("room:" <> room_id), do: room_id
  defp room_id_from_scope(_scope), do: "placeholder"

  defp timeout_metadata_timestamp(receipt_entry) do
    metadata = receipt_entry["phase_metadata"] || %{}
    receipt = receipt_entry["receipt"] || %{}

    metadata["accepted_at"] ||
      metadata["published_at"] ||
      metadata["receipt_stored_at"] ||
      receipt["delivered_at"]
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, parsed, _offset} -> parsed
      _ -> nil
    end
  end

  defp expired?(timestamp, state) when is_binary(timestamp) do
    case monotonic_deadline_ms(timestamp, state) do
      deadline_ms when is_integer(deadline_ms) -> current_monotonic_ms(state) > deadline_ms
      nil -> true
    end
  end

  defp timeout_ms_for_pending(command, default_timeout_ms, _state) do
    case command_lifetime_ms(command) do
      lifetime_ms when is_integer(lifetime_ms) and lifetime_ms > 0 ->
        min(default_timeout_ms, lifetime_ms)

      _ ->
        default_timeout_ms
    end
  end

  defp remaining_until(%DateTime{} = deadline, state) do
    delta_ms = DateTime.diff(deadline, state.started_at_utc, :millisecond)
    deadline_ms = state.started_monotonic_ms + delta_ms
    deadline_ms - current_monotonic_ms(state)
  end

  defp monotonic_deadline_ms(timestamp, state) when is_binary(timestamp) do
    case parse_timestamp(timestamp) do
      %DateTime{} = deadline ->
        delta_ms = DateTime.diff(deadline, state.started_at_utc, :millisecond)
        state.started_monotonic_ms + delta_ms

      nil ->
        nil
    end
  end

  defp command_lifetime_ms(command) do
    with issued_at when is_binary(issued_at) <- command.issued_at,
         expires_at when is_binary(expires_at) <- command.expires_at,
         %DateTime{} = issued_dt <- parse_timestamp(issued_at),
         %DateTime{} = expires_dt <- parse_timestamp(expires_at) do
      max(0, DateTime.diff(expires_dt, issued_dt, :millisecond))
    else
      _ -> nil
    end
  end

  defp current_utc(state), do: state.utc_now.()
  defp current_monotonic_ms(state), do: state.monotonic_now_ms.()

  defp event_type(%module{}) do
    cond do
      module == Eigenforge.Contracts.ReasonerOutcome -> "reasoner_outcome_recorded"
      module == Eigenforge.Contracts.CapabilityCheck -> "capability_check_recorded"
      module == Eigenforge.Contracts.PolicyDecision -> "policy_decision_recorded"
      module == Eigenforge.Contracts.CommandEnvelope -> "command_envelope_issued"
      module == Eigenforge.Contracts.AfterActionEvent -> "after_action_recorded"
    end
  end

  defp subscribe(room_id, registry_name) do
    case PubSub.subscribe(room_topic(room_id), registry_name: registry_name) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> :ok
    end
  end

  defp subscribe_faults(registry_name) do
    case Eigenforge.Core.IoFaultStatus.subscribe(registry_name) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> :ok
    end
  end

  defp event_refs(snapshot) do
    %{
      reasoner_event_id:
        TraceIdentity.stable_id("event", ["reasoner_outcome_recorded", snapshot.snapshot_id]),
      capability_event_id:
        TraceIdentity.stable_id("event", ["capability_check_recorded", snapshot.snapshot_id]),
      policy_event_id:
        TraceIdentity.stable_id("event", ["policy_decision_recorded", snapshot.snapshot_id]),
      stale_deny_event_id:
        TraceIdentity.stable_id("event", ["stale_snapshot_denied", snapshot.snapshot_id]),
      command_event_id:
        TraceIdentity.stable_id("event", ["command_envelope_issued", snapshot.snapshot_id]),
      after_action_event_id:
        TraceIdentity.stable_id("event", ["after_action_recorded", snapshot.snapshot_id]),
      consensus_decision_id: TraceIdentity.stable_id("consensus", [snapshot.snapshot_id]),
      correlation_id: TraceIdentity.stable_id("correlation", [snapshot.snapshot_id])
    }
  end

  defp event_id_for("reasoner_outcome_recorded", refs), do: refs.reasoner_event_id
  defp event_id_for("capability_check_recorded", refs), do: refs.capability_event_id
  defp event_id_for("policy_decision_recorded", refs), do: refs.policy_event_id
  defp event_id_for("stale_snapshot_denied", refs), do: refs.stale_deny_event_id
  defp event_id_for("command_envelope_issued", refs), do: refs.command_event_id
  defp event_id_for("after_action_recorded", refs), do: refs.after_action_event_id

  defp room_topic(room_id), do: "io_state:room:#{room_id}"
end
