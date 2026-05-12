defmodule Eigenforge.Core.AfterActionObserver do
  @moduledoc """
  V1 after-action interpretation helpers.
  """

  alias Eigenforge.Contracts.AfterActionEvent
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.TraceIdentity

  @terminal_statuses ~w(
    confirmed_changed
    confirmed_already_in_state
    adapter_rejected
    adapter_failed
    state_mismatch
    timed_out
  )

  @type observation :: %{
          optional(:observed_state) => String.t() | nil,
          optional(:source_observation_id) => String.t() | nil,
          optional(:source_received_seq) => integer() | nil,
          optional(:source_received_monotonic_ms) => integer() | nil,
          optional(:reported_at) => String.t() | nil
        }

  @type fault :: %{
          optional(:fault_type) => String.t() | nil,
          optional(:event_id) => String.t() | nil,
          optional(:source_received_seq) => integer() | nil,
          optional(:source_received_monotonic_ms) => integer() | nil,
          optional(:reported_at) => String.t() | nil
        }

  @spec observe(CommandEnvelope.t() | nil) :: {:ok, AfterActionEvent.t() | nil}
  def observe(nil), do: {:ok, nil}

  def observe(%CommandEnvelope{} = command) do
    {:ok,
     AfterActionEvent.new!(%{
       after_action_id: TraceIdentity.stable_id("after-action", [command.command_id]),
       command_id: command.command_id,
       idempotency_key: command.idempotency_key,
       effect_key: command.effect_key,
       adapter_attempt_id: TraceIdentity.stable_id("adapter-attempt", [command.command_id]),
       target: command.target,
       requested_state: command.requested_state,
       observed_state: command.requested_state,
       status: "confirmed_changed",
       observed_at: timestamp(),
       reported_at: timestamp(),
       source_observation_ids: [TraceIdentity.stable_id("sim-observation", [command.command_id])],
       source_fault_event_ids: []
     })}
  end

  @doc """
  Interprets a post-delivery actuator observation into a terminal after-action
  event when the IO-local receive ordering proves the evidence arrived after the
  command was accepted for delivery.
  """
  @spec interpret_observation(CommandEnvelope.t(), map(), observation()) ::
          {:ok, AfterActionEvent.t()} | {:error, term()}
  def interpret_observation(%CommandEnvelope{} = command, pre_command_snapshot, observation)
      when is_map(pre_command_snapshot) and is_map(observation) do
    with :ok <- validate_observation_order(pre_command_snapshot, observation),
         {:ok, status} <- observation_status(command, pre_command_snapshot, observation) do
      {:ok,
       build_after_action(command, %{
         status: status,
         observed_state: Map.get(observation, :observed_state) || Map.get(observation, "observed_state"),
         source_observation_ids: [Map.get(observation, :source_observation_id) || Map.get(observation, "source_observation_id")],
         source_fault_event_ids: [],
         observed_at: Map.get(observation, :reported_at) || Map.get(observation, "reported_at") || timestamp(),
         reported_at: Map.get(observation, :reported_at) || Map.get(observation, "reported_at") || timestamp()
       })}
    end
  end

  @doc """
  Interprets a terminal adapter fault into a terminal after-action event.
  """
  @spec interpret_fault(CommandEnvelope.t(), fault(), map() | nil) ::
          {:ok, AfterActionEvent.t()} | {:error, term()}
  def interpret_fault(%CommandEnvelope{} = command, fault, pre_command_snapshot \\ nil)
      when is_map(fault) do
    with :ok <- validate_observation_order(pre_command_snapshot || command, fault),
         {:ok, status} <- fault_status(fault) do
      {:ok,
       build_after_action(command, %{
         status: status,
         observed_state: nil,
         source_observation_ids: [],
         source_fault_event_ids: [Map.get(fault, :event_id) || Map.get(fault, "event_id")],
         observed_at: Map.get(fault, :reported_at) || Map.get(fault, "reported_at") || timestamp(),
         reported_at: Map.get(fault, :reported_at) || Map.get(fault, "reported_at") || timestamp()
       })}
    end
  end

  @doc """
  Records a timeout when no confirming observation or terminal adapter fault
  arrives before the configured deadline.
  """
  @spec timeout(CommandEnvelope.t(), keyword()) :: {:ok, AfterActionEvent.t()}
  def timeout(%CommandEnvelope{} = command, opts \\ []) do
    observed_at = Keyword.get(opts, :reported_at, timestamp())

    {:ok,
     build_after_action(command, %{
       status: "timed_out",
       observed_state: nil,
       source_observation_ids: [],
       source_fault_event_ids: [],
       observed_at: observed_at,
       reported_at: observed_at
     })}
  end

  @doc """
  Returns true when an after-action status is one of the V1 terminal statuses.
  """
  @spec terminal_status?(String.t() | nil) :: boolean()
  def terminal_status?(status), do: status in @terminal_statuses

  defp observation_status(command, pre_command_snapshot, observation) do
    observed_state = Map.get(observation, :observed_state) || Map.get(observation, "observed_state")
    pre_command_state = pre_command_fan_state(pre_command_snapshot)

    cond do
      observed_state == command.requested_state and pre_command_state == command.requested_state ->
        {:ok, "confirmed_already_in_state"}

      observed_state == command.requested_state ->
        {:ok, "confirmed_changed"}

      is_binary(observed_state) and observed_state != "" ->
        {:ok, "state_mismatch"}

      true ->
        {:error, :missing_observed_state}
    end
  end

  defp fault_status(fault) do
    case Map.get(fault, :fault_type) || Map.get(fault, "fault_type") do
      "adapter_rejected" -> {:ok, "adapter_rejected"}
      "adapter_execution_failed" -> {:ok, "adapter_failed"}
      "adapter_failed" -> {:ok, "adapter_failed"}
      "command_expired" -> {:ok, "timed_out"}
      other -> {:error, {:unsupported_fault_type, other}}
    end
  end

  defp validate_observation_order(pre_command_snapshot, evidence) do
    command_seq = accepted_seq(pre_command_snapshot)
    command_ms = accepted_monotonic_ms(pre_command_snapshot)
    evidence_seq = Map.get(evidence, :source_received_seq) || Map.get(evidence, "source_received_seq")
    evidence_ms = Map.get(evidence, :source_received_monotonic_ms) || Map.get(evidence, "source_received_monotonic_ms")

    cond do
      is_integer(command_seq) and is_integer(evidence_seq) and evidence_seq > command_seq ->
        :ok

      is_integer(command_ms) and is_integer(evidence_ms) and evidence_ms > command_ms ->
        :ok

      true ->
        {:error, :stale_confirmation_evidence}
    end
  end

  defp accepted_seq(snapshot) do
    case snapshot do
      %CommandEnvelope{} = command ->
        Map.get(command, :snapshot_seq)

      map when is_map(map) ->
        map
        |> Map.get("source_received_seq", %{})
        |> Map.get("fan")

      _ ->
        nil
    end
  end

  defp accepted_monotonic_ms(snapshot) do
    case snapshot do
      %CommandEnvelope{} = command ->
        command
        |> Map.get(:metadata, %{})
        |> case do
          map when is_map(map) ->
            Map.get(map, "command_source_received_monotonic_ms") || Map.get(map, :command_source_received_monotonic_ms)

          _ ->
            nil
        end

      map when is_map(map) ->
        map
        |> Map.get("source_received_monotonic_ms", %{})
        |> Map.get("fan")

      _ ->
        nil
    end
  end

  defp pre_command_fan_state(snapshot) do
    Map.get(snapshot, :fan_state) || Map.get(snapshot, "fan_state")
  end

  defp build_after_action(command, attrs) do
    AfterActionEvent.new!(%{
      after_action_id: TraceIdentity.stable_id("after-action", [command.command_id, attrs.status, attrs.reported_at]),
      command_id: command.command_id,
      idempotency_key: command.idempotency_key,
      effect_key: command.effect_key,
      adapter_attempt_id: TraceIdentity.stable_id("adapter-attempt", [command.command_id]),
      target: command.target,
      requested_state: command.requested_state,
      observed_state: attrs.observed_state,
      status: attrs.status,
      observed_at: attrs.observed_at,
      reported_at: attrs.reported_at,
      source_observation_ids: Enum.reject(attrs.source_observation_ids, &is_nil/1),
      source_fault_event_ids: Enum.reject(attrs.source_fault_event_ids, &is_nil/1)
    })
  end

  defp timestamp, do: CanonicalTime.trace_start()
end
