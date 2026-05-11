defmodule Eigenforge.IO.HomeAssistantTransport.LiveTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.IO.HomeAssistantTransport.Live

  defmodule FakeHomeAssistantPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(%Plug.Conn{method: "GET", path_info: ["api", "websocket"]} = conn, opts) do
      conn
      |> WebSockAdapter.upgrade(Eigenforge.IO.HomeAssistantTransport.LiveTest.FakeHomeAssistantWebSock, opts, timeout: 60_000)
      |> halt()
    end

    def call(%Plug.Conn{method: "POST", path_info: ["api", "services", domain, service]} = conn, opts) do
      {:ok, body, conn} = read_body(conn)
      payload = Contracts.decode_json!(body)
      Agent.update(opts[:server], fn state ->
        update_in(state.service_calls, &[Map.put(payload, "domain", domain) |> Map.put("service", service) | &1])
      end)

      send_resp(conn, 200, ~s({"accepted":true}))
    end

    def call(conn, _opts), do: send_resp(conn, 404, "not found")
  end

  defmodule FakeHomeAssistantWebSock do
    @behaviour WebSock

    alias Eigenforge.Contracts

    def init(opts) do
      send(opts[:test_pid], {:fake_ha_ws, self()})
      {:push, {:text, Contracts.canonical_json(%{"type" => "auth_required"})}, Map.merge(%{subscription_id: nil}, Map.new(opts))}
    end

    def handle_in({payload, [opcode: :text]}, state) do
      message = Contracts.decode_json!(payload)

      case message["type"] do
        "auth" ->
          if message["access_token"] == "token" do
            {:push, {:text, Contracts.canonical_json(%{"type" => "auth_ok"})}, state}
          else
            {:push, {:text, Contracts.canonical_json(%{"type" => "auth_invalid", "message" => "bad token"})}, state}
          end

        "get_states" ->
          states = Agent.get(state.server, &Map.values(&1.states))

          {:push,
           {:text,
            Contracts.canonical_json(%{
              "id" => message["id"],
              "type" => "result",
              "success" => true,
              "result" => states
            })}, state}

        "subscribe_events" ->
          {:push,
           {:text,
            Contracts.canonical_json(%{
              "id" => message["id"],
              "type" => "result",
              "success" => true,
              "result" => nil
            })}, %{state | subscription_id: message["id"]}}
      end
    end

    def handle_info({:emit_state_changed, entity_id, next_state}, state) do
      event =
        %{
          "id" => state.subscription_id,
          "type" => "event",
          "event" => %{
            "event_type" => "state_changed",
            "time_fired" => next_state["last_updated"],
            "data" => %{
              "entity_id" => entity_id,
              "new_state" => next_state,
              "old_state" => nil
            }
          }
        }

      {:push, {:text, Contracts.canonical_json(event)}, state}
    end
  end

  setup do
    {:ok, server} =
      start_supervised(
        {Agent,
         fn ->
           %{
             service_calls: [],
             states: %{
               "sensor.placeholder_co2" => state_payload("sensor.placeholder_co2", "1200", "ctx-co2-1", "2026-05-11T00:00:00.000Z"),
               "sensor.placeholder_humidity" => state_payload("sensor.placeholder_humidity", "45.0", "ctx-humidity-1", "2026-05-11T00:00:00.000Z"),
               "sensor.placeholder_temperature" => state_payload("sensor.placeholder_temperature", "22.0", "ctx-temperature-1", "2026-05-11T00:00:00.000Z"),
               "switch.placeholder_fan" => state_payload("switch.placeholder_fan", "off", "ctx-fan-1", "2026-05-11T00:00:00.000Z")
             }
           }
         end}
      )

    port = free_port()

    bandit =
      start_supervised!(
        {Bandit,
         plug: {FakeHomeAssistantPlug, [server: server, test_pid: self()]},
         scheme: :http,
         port: port}
      )

    on_exit(fn ->
      if Process.alive?(bandit), do: Process.exit(bandit, :normal)
    end)

    %{
      base_url: "http://127.0.0.1:#{port}",
      entity_ids: %{
        co2: "sensor.placeholder_co2",
        humidity: "sensor.placeholder_humidity",
        temperature: "sensor.placeholder_temperature",
        fan: "switch.placeholder_fan"
      },
      server: server
    }
  end

  test "connect authenticates, loads initial states, and forwards live state updates", %{
    base_url: base_url,
    entity_ids: entity_ids
  } do
    assert {:ok, conn, states} = Live.connect(base_url, "token", entity_ids: entity_ids)
    assert states["sensor.placeholder_co2"]["status"] == "fresh"
    assert states["switch.placeholder_fan"]["state"] == "off"
    assert conn.base_url == base_url
    assert is_pid(conn.socket)

    assert_receive {:fake_ha_ws, ws_pid}, 1_000
    assert is_pid(ws_pid)

    send(
      ws_pid,
      {:emit_state_changed, "switch.placeholder_fan",
       state_payload("switch.placeholder_fan", "on", "ctx-fan-2", "2026-05-11T00:00:01.000Z")}
    )

    assert_receive {:home_assistant_transport_snapshot, ^conn, next_states}, 1_500
    assert next_states["switch.placeholder_fan"]["state"] == "on"
    assert next_states["switch.placeholder_fan"]["observation_id"] == "ctx-fan-2"
    assert next_states["switch.placeholder_fan"]["received_seq"] > states["switch.placeholder_fan"]["received_seq"]
  end

  test "command posts Home Assistant service calls over REST", %{
    base_url: base_url,
    entity_ids: entity_ids,
    server: server
  } do
    assert {:ok, conn, _states} = Live.connect(base_url, "token", entity_ids: entity_ids)

    assert {:ok, %{"accepted" => true, "status" => 200}} =
             Live.command(conn, %{
               "domain" => "switch",
               "service" => "turn_on",
               "entity_id" => "switch.placeholder_fan"
             })

    calls = Agent.get(server, & &1.service_calls)
    assert [%{"domain" => "switch", "service" => "turn_on", "entity_id" => "switch.placeholder_fan"}] = calls
  end

  defp state_payload(entity_id, state, context_id, observed_at) do
    %{
      "entity_id" => entity_id,
      "state" => state,
      "last_changed" => observed_at,
      "last_updated" => observed_at,
      "context" => %{"id" => context_id}
    }
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
