defmodule Eigenforge.Core.SnapshotSubscriber do
  @moduledoc """
  Supervised OODA pipeline entrypoint for normalized snapshots.
  """

  use GenServer

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Core.AfterActionObserver
  alias Eigenforge.Core.CapabilityChecker
  alias Eigenforge.Core.CommandIssuer
  alias Eigenforge.Core.LedgerProjections
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.PolicyEngine
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
    pubsub_registry = Keyword.get(opts, :pubsub_registry, Eigenforge.Core.PubSub.Registry)
    :ok = subscribe(room_id, pubsub_registry)

    {:ok,
     %{
       room_id: room_id,
       mailbox_registry: Keyword.get(opts, :mailbox_registry, Eigenforge.Mailbox.Registry),
       writer: Keyword.get(opts, :writer, LedgerWriter),
       db_path: Keyword.get(opts, :db_path),
       reasoner_module: Keyword.get(opts, :reasoner_module, Co2Rules),
       after_action_observer: Keyword.get(opts, :after_action_observer, AfterActionObserver),
       secret: Keyword.fetch!(opts, :secret),
       processed_snapshot_ids: MapSet.new()
     }}
  end

  @impl true
  def handle_info({:core_pubsub, topic, snapshot_payload}, state) do
    state =
      if topic == room_topic(state.room_id) do
        case normalize_snapshot(snapshot_payload) do
          {:ok, snapshot} ->
            if MapSet.member?(state.processed_snapshot_ids, snapshot.snapshot_id) do
              state
            else
              _ = run_pipeline(snapshot, state)
              %{state | processed_snapshot_ids: MapSet.put(state.processed_snapshot_ids, snapshot.snapshot_id)}
            end

          {:error, _reason} ->
            state
        end
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run_pipeline(snapshot, state) do
    refs = event_refs(snapshot)

    with {:ok, reasoner} <- state.reasoner_module.reason(snapshot),
         {:ok, capability} <- CapabilityChecker.check(reasoner, snapshot),
         {:ok, policy} <- PolicyEngine.decide(reasoner, capability, snapshot),
         {:ok, command} <-
           CommandIssuer.issue(reasoner, capability, policy, snapshot, state.secret,
             consensus_decision_id: refs.consensus_decision_id,
             decision_event_id: refs.command_event_id,
             reasoner_outcome_event_id: refs.reasoner_event_id,
             capability_event_id: refs.capability_event_id
           ),
         {:ok, guarded_command} <- apply_in_flight_guard(command, snapshot.room_id, state),
         {:ok, after_action} <- state.after_action_observer.observe(guarded_command),
         payloads <- [reasoner, capability, policy, guarded_command, after_action] |> Enum.reject(&is_nil/1),
         :ok <- append_payloads(payloads, snapshot, refs, state) do
      if guarded_command do
        CommandPublisher.publish("commands:io", Contracts.signable_map(guarded_command),
          registry_name: state.mailbox_registry
        )
      end

      :ok
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
    Enum.reduce_while(payloads, :ok, fn payload, :ok ->
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
        {:ok, _event} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_snapshot(%NormalizedSnapshot{} = snapshot), do: {:ok, snapshot}

  defp normalize_snapshot(snapshot) when is_map(snapshot) do
    {:ok, NormalizedSnapshot.new!(snapshot)}
  rescue
    error -> {:error, {:invalid_snapshot, Exception.message(error)}}
  end

  defp event_type(%Eigenforge.Contracts.PolicyDecision{decision: "deny_stale_snapshot"}),
    do: "stale_snapshot_denied"

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

  defp event_refs(snapshot) do
    %{
      reasoner_event_id: TraceIdentity.stable_id("event", ["reasoner_outcome_recorded", snapshot.snapshot_id]),
      capability_event_id: TraceIdentity.stable_id("event", ["capability_check_recorded", snapshot.snapshot_id]),
      policy_event_id: TraceIdentity.stable_id("event", ["policy_decision_recorded", snapshot.snapshot_id]),
      stale_deny_event_id: TraceIdentity.stable_id("event", ["stale_snapshot_denied", snapshot.snapshot_id]),
      command_event_id: TraceIdentity.stable_id("event", ["command_envelope_issued", snapshot.snapshot_id]),
      after_action_event_id: TraceIdentity.stable_id("event", ["after_action_recorded", snapshot.snapshot_id]),
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
