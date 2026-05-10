defmodule Eigenforge.Core.AfterActionObserver do
  @moduledoc """
  V1 simulator-path after-action observer.
  """

  alias Eigenforge.Contracts.AfterActionEvent
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.TraceIdentity

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

  defp timestamp, do: CanonicalTime.trace_start()
end
