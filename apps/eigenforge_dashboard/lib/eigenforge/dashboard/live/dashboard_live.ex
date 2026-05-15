defmodule Eigenforge.Dashboard.DashboardLive do
  use Phoenix.LiveView

  alias Eigenforge.Core.Redaction
  alias Eigenforge.Dashboard.DashboardState
  alias Eigenforge.Mailbox.LedgerNotifier

  @refresh_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: subscribe_to_ledger_notifier()

    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(:page_title, "Eigenforge Dashboard")
     |> assign(:state, %{})
     |> assign(:error, nil)
     |> load_state()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_state(socket)}
  end

  @impl true
  def handle_info({:mailbox_command, "ledger_events:committed", %{"notification" => _notification}}, socket) do
    {:noreply, load_state(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="panel hero">
      <div class="hero-copy">
        <p class="eyebrow">Eigenforge V1</p>
        <h1>Read-only control surface</h1>
        <p class="lede">
          Live IO state and durable decision history are shown together, but this
          dashboard never issues commands.
        </p>
      </div>
      <div class="hero-meta">
        <div>
          <span class="meta-label">Mode</span>
          <strong><%= dash(@state["io_mode"]) %></strong>
        </div>
        <div>
          <span class="meta-label">Connection</span>
          <strong class={status_class(@state["connection_status"])}><%= dash(@state["connection_status"]) %></strong>
        </div>
        <div>
          <span class="meta-label">Freshness</span>
          <strong class={status_class(@state["freshness"])}><%= dash(@state["freshness"]) %></strong>
        </div>
      </div>
    </section>

    <p :if={@error} class="error-banner"><%= @error %></p>

    <section class="grid">
      <article class="panel stat">
        <span class="card-label">CO2</span>
        <strong><%= reading(@state["sensor_state"], "co2_ppm") %> ppm</strong>
        <span class={status_class(get_in(@state, ["sensor_state", "co2_status"]))}>
          <%= dash(get_in(@state, ["sensor_state", "co2_status"])) %>
        </span>
      </article>

      <article class="panel stat">
        <span class="card-label">Humidity</span>
        <strong><%= humidity_reading(@state["sensor_state"]) %></strong>
        <span class={status_class(get_in(@state, ["sensor_state", "humidity_status"]))}>
          <%= dash(get_in(@state, ["sensor_state", "humidity_status"])) %>
        </span>
      </article>

      <article class="panel stat">
        <span class="card-label">Temperature</span>
        <strong><%= temperature_reading(@state["sensor_state"]) %></strong>
        <span class={status_class(get_in(@state, ["sensor_state", "temperature_status"]))}>
          <%= dash(get_in(@state, ["sensor_state", "temperature_status"])) %>
        </span>
      </article>

      <article class="panel stat">
        <span class="card-label">Fan</span>
        <strong><%= dash(get_in(@state, ["fan_state", "state"])) %></strong>
        <span class={status_class(get_in(@state, ["fan_state", "status"]))}>
          <%= dash(get_in(@state, ["fan_state", "status"])) %>
        </span>
      </article>
    </section>

    <section class="grid two-up">
      <article class="panel detail">
        <h2>Control Summary</h2>
        <dl>
          <div><dt>Room</dt><dd><%= dash(@state["room_id"]) %></dd></div>
          <div><dt>Simulator</dt><dd><%= if @state["simulator_mode"], do: "yes", else: "no" %></dd></div>
          <div><dt>Stale alert</dt><dd><%= if @state["stale_sensor_alert"], do: "active", else: "clear" %></dd></div>
          <div><dt>Reasoner outcome</dt><dd><%= dash(@state["reasoner_outcome"]) %></dd></div>
          <div><dt>Policy decision</dt><dd><%= dash(@state["policy_decision"]) %></dd></div>
          <div><dt>Last command</dt><dd><%= dash(@state["last_command_id"]) %></dd></div>
          <div><dt>After-action</dt><dd><%= dash(@state["after_action_status"]) %></dd></div>
          <div><dt>Lifecycle</dt><dd><%= dash(@state["command_lifecycle"]) %></dd></div>
        </dl>
      </article>

      <article class="panel detail">
        <h2>Recent IO Events</h2>
        <ul class="event-list detailed-events">
          <li :for={event <- @state["recent_io_events"] || []}>
            <div>
              <strong><%= event["payload"]["fault_type"] %></strong>
              <p><%= dash(event["payload"]["source"]) %> · <%= event["event_type"] %></p>
            </div>
            <span><%= event["persisted_at"] %></span>
          </li>
          <li :if={Enum.empty?(@state["recent_io_events"] || [])}>No recent IO events.</li>
        </ul>
      </article>
    </section>

    <section class="grid two-up">
      <article class="panel detail">
        <h2>Recent Control Chains</h2>
        <ul class="event-list">
          <li :for={chain <- @state["recent_control_chains"] || []}>
            <strong><%= dash(chain["reasoner_outcome"]) %> → <%= dash(chain["policy_decision"]) %></strong>
            <span><%= dash(chain["after_action_status"]) %></span>
          </li>
          <li :if={Enum.empty?(@state["recent_control_chains"] || [])}>No durable control chains yet.</li>
        </ul>
      </article>

      <article class="panel detail">
        <h2>Recent Ledger Events</h2>
        <ul class="event-list">
          <li :for={event <- @state["recent_ledger_events"] || []}>
            <strong><%= event["event_type"] %></strong>
            <span><%= event["persisted_at"] %></span>
          </li>
          <li :if={Enum.empty?(@state["recent_ledger_events"] || [])}>No recent ledger events yet.</li>
        </ul>
      </article>
    </section>

    <style>
      .hero {
        display: grid;
        grid-template-columns: 1.7fr 1fr;
        gap: 24px;
        padding: 28px;
        margin-bottom: 20px;
      }

      .eyebrow, .meta-label, .card-label {
        text-transform: uppercase;
        letter-spacing: 0.14em;
        font-size: 0.72rem;
        color: var(--muted);
      }

      .hero h1 {
        margin: 8px 0 10px;
        font-size: clamp(2.2rem, 5vw, 4rem);
        line-height: 0.96;
      }

      .lede {
        max-width: 42rem;
        color: var(--muted);
        font-size: 1.05rem;
      }

      .hero-meta {
        display: grid;
        gap: 14px;
        align-content: start;
        padding: 18px;
        border-radius: 18px;
        background: linear-gradient(180deg, rgba(182, 81, 45, 0.09), rgba(255,255,255,0.4));
      }

      .hero-meta strong {
        display: block;
        margin-top: 4px;
        font-size: 1.1rem;
      }

      .grid {
        display: grid;
        gap: 18px;
        margin-top: 18px;
      }

      .grid.two-up {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .stat {
        padding: 20px;
      }

      .stat strong {
        display: block;
        margin: 6px 0;
        font-size: 2rem;
      }

      .detail {
        padding: 22px;
      }

      .detail h2 {
        margin-top: 0;
        font-size: 1.15rem;
      }

      dl {
        margin: 0;
        display: grid;
        gap: 10px;
      }

      dl div {
        display: flex;
        justify-content: space-between;
        gap: 16px;
        padding-bottom: 10px;
        border-bottom: 1px solid var(--border);
      }

      dt { color: var(--muted); }
      dd { margin: 0; text-align: right; }

      .event-list {
        list-style: none;
        padding: 0;
        margin: 0;
        display: grid;
        gap: 10px;
      }

      .event-list li {
        display: flex;
        justify-content: space-between;
        gap: 16px;
        padding: 12px 0;
        border-bottom: 1px solid var(--border);
      }

      .detailed-events p {
        margin: 4px 0 0;
        color: var(--muted);
        font-size: 0.9rem;
      }

      .status-ok { color: var(--ok); }
      .status-warn { color: var(--warn); }
      .status-bad { color: var(--bad); }
      .status-neutral { color: var(--muted); }

      .error-banner {
        margin: 0 0 12px;
        padding: 12px 16px;
        border-radius: 14px;
        background: rgba(158, 42, 43, 0.1);
        color: var(--bad);
      }

      @media (max-width: 840px) {
        .hero, .grid.two-up {
          grid-template-columns: 1fr;
        }
      }

      @media (min-width: 720px) {
        .grid:not(.two-up) {
          grid-template-columns: repeat(4, minmax(0, 1fr));
        }
      }
    </style>
    """
  end

  defp load_state(socket) do
    case DashboardState.load() do
      {:ok, state} ->
        socket |> assign(:state, state) |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(
          :error,
          reason
          |> inspect()
          |> Redaction.redact(secrets: DashboardState.redaction_secrets())
        )
    end
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  defp subscribe_to_ledger_notifier do
    _ = LedgerNotifier.subscribe()
  end

  defp dash(nil), do: "not_yet_observed"
  defp dash(""), do: "not_yet_observed"
  defp dash(value), do: to_string(value)

  defp reading(nil, _key), do: "0"
  defp reading(map, key), do: map[key] || 0

  defp humidity_reading(nil), do: "0.00%"
  defp humidity_reading(map), do: percent_from_basis_points(map["humidity_basis_points"])

  defp temperature_reading(nil), do: "0.0 C"
  defp temperature_reading(map), do: celsius_from_millicelsius(map["temperature_millicelsius"])

  defp percent_from_basis_points(nil), do: "0.00%"
  defp percent_from_basis_points(value), do: :erlang.float_to_binary(value / 100, decimals: 2) <> "%"

  defp celsius_from_millicelsius(nil), do: "0.0 C"
  defp celsius_from_millicelsius(value), do: :erlang.float_to_binary(value / 1000, decimals: 1) <> " C"

  defp status_class(status) when status in ["fresh", "allow", "confirmed_changed", "confirmed_already_in_state", "recovered", "connection_up"],
    do: "status-ok"

  defp status_class(status) when status in ["stale", "degraded", "reconnecting", "pending_command", "not_checked"],
    do: "status-warn"

  defp status_class(status) when status in ["adapter_failed", "adapter_rejected", "state_mismatch", "timed_out", "connection_down"],
    do: "status-bad"

  defp status_class(_status), do: "status-neutral"
end
