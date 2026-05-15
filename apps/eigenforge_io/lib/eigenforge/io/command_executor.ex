defmodule Eigenforge.IO.CommandExecutor do
  @moduledoc """
  Command verification and dispatch extracted from HomeAssistantClient.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.IO.ActuatorStub
  alias Eigenforge.IO.CommandExecutionStore
  alias Eigenforge.IO.HomeAssistantAdapter
  alias Eigenforge.Mailbox.CommandPublisher

  @spec execute(map(), map()) :: {:ok, term()} | {:error, term()}
  def execute(%{"command" => command, "receipt" => receipt}, state)
      when is_map(command) and is_map(receipt) do
    with :ok <- verify_delivery(command, receipt, state),
         {:ok, result} <- execute(command, state),
         :ok <-
           CommandPublisher.mark_io_accepted(
             receipt["receipt_id"],
             %{
               accepted_at: timestamp(state),
               accepted_monotonic_ms: current_monotonic_ms(state)
             },
             receipt_store: state.mailbox_receipt_store
           ) do
      {:ok, result}
    end
  end

  def execute(command, state) when is_map(command) do
    dispatch_command(command, Map.put(state, :current_command, command))
  end

  defp verify_delivery(command, receipt, state) do
    cond do
      not valid_signature?(
        command,
        command["signature"],
        state.hmac_secret,
        "eigenforge:v1:command_envelope"
      ) ->
        {:error, :invalid_command_signature}

      not valid_signature?(
        receipt,
        receipt["signature"],
        state.hmac_secret,
        "eigenforge:v1:delivery_receipt"
      ) ->
        {:error, :invalid_delivery_receipt_signature}

      receipt["command_id"] != command["command_id"] ->
        {:error, :receipt_command_mismatch}

      receipt["decision_event_id"] != command["decision_event_id"] ->
        {:error, :receipt_decision_mismatch}

      blank?(receipt["ledger_event_hash"]) ->
        {:error, :missing_committed_ledger_reference}

      not is_integer(receipt["ledger_sequence"]) or receipt["ledger_sequence"] <= 0 ->
        {:error, :missing_committed_ledger_reference}

      command_expired?(command, state) ->
        {:error, :command_expired}

      true ->
        :ok
    end
  end

  defp dispatch_command(%{"target" => target, "requested_state" => requested_state}, _state)
       when target in ["actuator:light", "actuator:laser", "actuator:piezo_beeper"] do
    ActuatorStub.execute(target, requested_state)
  end

  defp dispatch_command(
         %{"target" => "actuator:fan", "requested_state" => requested_state},
         state
       ) do
    cond do
      not state.connected? ->
        {:error, :not_connected}

      not state.physical_control_enabled? ->
        {:error, :physical_control_disabled}

      CommandExecutionStore.already_executed?(
        state.command_execution_store,
        state.current_command["idempotency_key"]
      ) ->
        {:error, :duplicate_idempotency_key}

      true ->
        with {:ok, request} <-
               HomeAssistantAdapter.command_request(
                 state.home_assistant.entity_ids.fan,
                 requested_state
               ),
             {:ok, result} <- state.transport.command(state.conn, request),
             :ok <-
               CommandExecutionStore.record(state.command_execution_store, %{
                 idempotency_key: state.current_command["idempotency_key"],
                 command_id: state.current_command["command_id"],
                 effect_key: state.current_command["effect_key"],
                 target: state.current_command["target"],
                 requested_state: state.current_command["requested_state"],
                 adapter_attempt_id: "adapter-attempt:" <> state.current_command["command_id"],
                 execution_status: "io_accepted",
                 recorded_at: timestamp(state)
               }) do
          maybe_notify_command_observer(state.command_observer, request, result)
          {:ok, result}
        end
    end
  end

  defp dispatch_command(%{"target" => target}, _state),
    do: {:error, {:unsupported_target, target}}

  defp dispatch_command(_command, _state), do: {:error, :invalid_command}

  defp maybe_notify_command_observer(nil, _request, _result), do: :ok

  defp maybe_notify_command_observer(pid, request, result) when is_pid(pid),
    do: send(pid, {:transport_command, request, result})

  defp timestamp(state) do
    state
    |> current_utc()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp current_utc(state), do: state.utc_now.()
  defp current_monotonic_ms(state), do: state.monotonic_now_ms.()
  defp blank?(value), do: value in [nil, ""]

  defp command_expired?(command, state) do
    case monotonic_deadline_ms(command["expires_at"], state) do
      deadline_ms when is_integer(deadline_ms) -> current_monotonic_ms(state) > deadline_ms
      nil -> true
    end
  end

  defp monotonic_deadline_ms(timestamp, state) do
    case absolute_deadline_ms(timestamp, state) do
      deadline_ms when is_integer(deadline_ms) ->
        if deadline_ms >= current_monotonic_ms(state), do: deadline_ms, else: nil

      _ ->
        nil
    end
  end

  defp absolute_deadline_ms(timestamp, state) do
    with {:ok, expires_at, _offset} <- DateTime.from_iso8601(timestamp) do
      delta_ms = DateTime.diff(expires_at, state.started_at_utc, :millisecond)
      state.started_monotonic_ms + delta_ms
    else
      _ -> nil
    end
  end

  defp valid_signature?(payload, signature, secret, purpose) when is_binary(signature) do
    Contracts.verify_hmac(payload, secret, signature, purpose)
  end

  defp valid_signature?(_payload, _signature, _secret, _purpose), do: false
end
