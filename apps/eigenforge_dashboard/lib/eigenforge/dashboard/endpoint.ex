defmodule Eigenforge.Dashboard.Endpoint do
  use Phoenix.Endpoint, otp_app: :eigenforge_dashboard

  socket "/live", Phoenix.LiveView.Socket

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Session,
    store: :cookie,
    key: "_eigenforge_dashboard_key",
    signing_salt: "dashboard-session"

  plug Eigenforge.Dashboard.Router
end
