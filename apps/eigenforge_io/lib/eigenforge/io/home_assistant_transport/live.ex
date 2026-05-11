defmodule Eigenforge.IO.HomeAssistantTransport.Live do
  @moduledoc """
  Live Home Assistant transport using the official WebSocket API for state
  ingest and REST service calls for fan commands.
  """

  use WebSockex

  alias Eigenforge.Contracts

  @behaviour Eigenforge.IO.HomeAssistantClient.Transport

  @connect_timeout 5_000

  @impl true
  @spec connect(String.t(), String.t()) :: {:ok, map(), map()} | {:error, term()}
  def connect(url, token) when is_binary(url) and is_binary(token) do
    connect(url, token, entity_ids: %{})
  end

  @impl true
  @spec connect(String.t(), String.t(), keyword()) :: {:ok, map(), map()} | {:error, term()}
  def connect(url, token, opts) when is_binary(url) and is_binary(token) and is_list(opts) do
    owner = self()
    entity_ids = Keyword.get(opts, :entity_ids, %{})

    with {:ok, pid} <-
           WebSockex.start_link(
             websocket_url(url),
             __MODULE__,
             %{
               owner: owner,
               token: token,
               entity_ids: normalize_entity_ids(entity_ids),
               base_url: normalize_base_url(url),
               states: %{},
               next_seq: 1,
               get_states_id: nil,
               subscription_id: nil,
               connected_notified?: false
             },
             handle_initial_conn_failure: true
           ) do
      receive do
        {:home_assistant_transport_connected, ^pid, states} ->
          {:ok, %{socket: pid, base_url: normalize_base_url(url), token: token}, states}

        {:home_assistant_transport_connect_failed, ^pid, reason} ->
          {:error, reason}
      after
        @connect_timeout ->
          Process.exit(pid, :normal)
          {:error, :connect_timeout}
      end
    end
  end

  @impl true
  @spec command(map(), map()) :: {:ok, map()} | {:error, term()}
  def command(%{base_url: base_url, token: token}, %{"domain" => domain, "service" => service, "entity_id" => entity_id})
      when is_binary(base_url) and is_binary(token) and is_binary(domain) and is_binary(service) and is_binary(entity_id) do
    body = Contracts.canonical_json(%{"entity_id" => entity_id})
    headers = [
      {~c"authorization", String.to_charlist("Bearer " <> token)},
      {~c"content-type", ~c"application/json"}
    ]

    request = {String.to_charlist(service_url(base_url, domain, service)), headers, ~c"application/json", body}

    case :httpc.request(:post, request, [], body_format: :binary) do
      {:ok, {{_, status, _reason_phrase}, _response_headers, response_body}} when status in [200, 201] ->
        {:ok, %{"accepted" => true, "status" => status, "body" => response_body}}

      {:ok, {{_, status, _reason_phrase}, _response_headers, response_body}} ->
        {:error, {:unexpected_status, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def command(_conn, request), do: {:error, {:invalid_command_request, request}}

  @impl true
  def handle_connect(_conn, state) do
    {:ok, state}
  end

  @impl true
  def handle_disconnect(_status_map, state) do
    send(state.owner, {:home_assistant_transport_closed, self(), :disconnected})
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, payload}, state) do
    case Contracts.decode_json(payload) do
      {:ok, %{"type" => "auth_required"}} ->
        auth = Contracts.canonical_json(%{"type" => "auth", "access_token" => state.token})
        {:reply, {:text, auth}, state}

      {:ok, %{"type" => "auth_ok"}} ->
        get_states_id = 1
        subscribe_id = 2
        send(self(), {:ha_transport_send, %{"id" => subscribe_id, "type" => "subscribe_events", "event_type" => "state_changed"}})

        {:reply, {:text, Contracts.canonical_json(%{"id" => get_states_id, "type" => "get_states"})},
         %{state | get_states_id: get_states_id, subscription_id: subscribe_id}}

      {:ok, %{"type" => "auth_invalid", "message" => message}} ->
        send(state.owner, {:home_assistant_transport_connect_failed, self(), {:auth_invalid, message}})
        {:close, state}

      {:ok, %{"type" => "result", "id" => id, "success" => true, "result" => result}} when id == state.get_states_id ->
        {states, next_seq} = build_initial_states(result, state.entity_ids, state.next_seq)
        send(state.owner, {:home_assistant_transport_connected, self(), states})
        {:ok, %{state | states: states, next_seq: next_seq, connected_notified?: true}}

      {:ok, %{"type" => "result", "id" => id, "success" => true}} when id == state.subscription_id ->
        {:ok, state}

      {:ok, %{"type" => "result", "id" => id, "success" => false, "error" => error}}
      when id == state.get_states_id or id == state.subscription_id ->
        send(state.owner, {:home_assistant_transport_connect_failed, self(), {:command_failed, error}})
        {:close, state}

      {:ok, %{"type" => "event", "id" => id, "event" => %{"event_type" => "state_changed", "data" => event_data} = event}}
      when id == state.subscription_id ->
        {next_states, next_seq} = apply_state_event(state.states, event_data, event, state.entity_ids, state.next_seq)

        if next_states != state.states do
          send(state.owner, {:home_assistant_transport_snapshot, %{socket: self(), base_url: state.base_url, token: state.token}, next_states})
        end

        {:ok, %{state | states: next_states, next_seq: next_seq}}

      {:ok, _message} ->
        {:ok, state}

      {:error, reason} ->
        if not state.connected_notified? do
          send(state.owner, {:home_assistant_transport_connect_failed, self(), {:invalid_payload, reason}})
        end

        {:close, state}
    end
  end

  @impl true
  def handle_info({:ha_transport_send, message}, state) do
    {:reply, {:text, Contracts.canonical_json(message)}, state}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  @spec websocket_url(String.t()) :: String.t()
  def websocket_url(url) when is_binary(url) do
    url
    |> normalize_base_url()
    |> String.replace_prefix("https://", "wss://")
    |> String.replace_prefix("http://", "ws://")
    |> Kernel.<>("/api/websocket")
  end

  @spec service_url(String.t(), String.t(), String.t()) :: String.t()
  def service_url(base_url, domain, service)
      when is_binary(base_url) and is_binary(domain) and is_binary(service) do
    normalize_base_url(base_url) <> "/api/services/" <> domain <> "/" <> service
  end

  defp apply_state_event(states, %{"entity_id" => entity_id, "new_state" => new_state}, event, entity_ids, next_seq)
       when is_map(new_state) do
    if tracked_entity?(entity_id, entity_ids) do
      monotonic_ms = System.monotonic_time(:millisecond)
      updated = to_raw_state(entity_id, new_state, event["time_fired"], next_seq, monotonic_ms, entity_ids)
      {Map.put(states, entity_id, updated), next_seq + 1}
    else
      {states, next_seq}
    end
  end

  defp apply_state_event(states, _event_data, _event, _entity_ids, next_seq), do: {states, next_seq}

  defp build_initial_states(result, entity_ids, next_seq) when is_list(result) do
    monotonic_ms = System.monotonic_time(:millisecond)

    states =
      result
      |> Enum.filter(fn
        %{"entity_id" => entity_id} -> tracked_entity?(entity_id, entity_ids)
        _ -> false
      end)
      |> Enum.reduce(%{}, fn %{"entity_id" => entity_id} = state, acc ->
        Map.put(acc, entity_id, to_raw_state(entity_id, state, nil, next_seq, monotonic_ms, entity_ids))
      end)

    {states, next_seq + 1}
  end

  defp normalize_base_url(url) do
    String.trim_trailing(url, "/")
  end

  defp tracked_entity?(entity_id, entity_ids) do
    entity_id in Map.values(entity_ids)
  end

  defp to_raw_state(entity_id, state, event_time, received_seq, monotonic_ms, entity_ids) do
    key = entity_key_for(entity_id, entity_ids)
    state_value = Map.get(state, "state")
    observed_at = Map.get(state, "last_updated") || Map.get(state, "last_changed") || event_time || timestamp()

    %{
      "entity_id" => entity_id,
      "entity_class" => entity_class(entity_id),
      "state" => state_value,
      "observation_id" => get_in(state, ["context", "id"]) || "#{entity_id}:#{observed_at}",
      "observed_at" => observed_at,
      "received_seq" => received_seq,
      "received_monotonic_ms" => monotonic_ms,
      "status" => status_for_state(key, state_value)
    }
  end

  defp entity_class(entity_id) do
    entity_id
    |> String.split(".", parts: 2)
    |> hd()
  end

  defp entity_key_for(entity_id, entity_ids) do
    Enum.find_value(entity_ids, fn {key, value} -> if value == entity_id, do: key end) || "unknown"
  end

  defp status_for_state(_key, nil), do: "missing"
  defp status_for_state(_key, "unknown"), do: "unknown"
  defp status_for_state(_key, "unavailable"), do: "unavailable"

  defp status_for_state("co2", value) do
    if integer_like?(value), do: "fresh", else: "malformed"
  end

  defp status_for_state(key, value) when key in ["humidity", "temperature"] do
    if float_like?(value) or integer_like?(value), do: "fresh", else: "malformed"
  end

  defp status_for_state("fan", value) when value in ["on", "off"], do: "fresh"
  defp status_for_state("fan", _value), do: "malformed"
  defp status_for_state(_key, _value), do: "fresh"

  defp integer_like?(value) when is_integer(value), do: true

  defp integer_like?(value) when is_binary(value) do
    case Integer.parse(value) do
      {_integer, ""} -> true
      _ -> false
    end
  end

  defp integer_like?(_value), do: false

  defp float_like?(value) when is_float(value), do: true
  defp float_like?(value) when is_integer(value), do: true

  defp float_like?(value) when is_binary(value) do
    case Float.parse(value) do
      {_float, ""} -> true
      _ -> false
    end
  end

  defp float_like?(_value), do: false

  defp normalize_entity_ids(entity_ids) do
    Map.new(entity_ids, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end
end
