import Config

config :eigenforge_core,
  hmac_secret: System.get_env("EIGENFORGE_HMAC_SECRET") || "eigenforge-v1-test-secret",
  reasoner_module: Eigenforge.Core.Reasoners.Co2Rules

config :eigenforge_mailbox,
  hmac_secret: System.get_env("EIGENFORGE_HMAC_SECRET") || "replace_me",
  receipt_store_path:
    System.get_env("EIGENFORGE_MAILBOX_RECEIPT_STORE_PATH") || "log/mailbox_receipts.json"

config :eigenforge_dashboard, Eigenforge.Dashboard.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: Eigenforge.Dashboard.ErrorHTML, json: Eigenforge.Dashboard.ErrorJSON],
    layout: false
  ],
  pubsub_server: Eigenforge.Dashboard.PubSub,
  live_view: [signing_salt: "eigenforge-dashboard"],
  secret_key_base:
    System.get_env("EIGENFORGE_DASHBOARD_SECRET_KEY_BASE") ||
      "eigenforge_dashboard_secret_key_base_for_local_testing_only",
  server: false

config :phoenix, :json_library, Jason

if config_env() == :test do
  config :eigenforge_core,
    runtime_env: %{
      "EIGENFORGE_IO_MODE" => "simulator",
      "EIGENFORGE_HMAC_SECRET" => "replace_me",
      "EIGENFORGE_CORE_NODE_ID" => "core_a",
      "EIGENFORGE_CORE_DB_PATH" => Path.join(System.tmp_dir!(), "eigenforge-core-test.sqlite3"),
      "EIGENFORGE_DEVICE_INVENTORY_PATH" => Path.expand("../config/devices.json", __DIR__),
      "EIGENFORGE_DEVICE_INVENTORY_SIG_PATH" => Path.expand("../config/devices.json.sig", __DIR__),
      "EIGENFORGE_CAPABILITY_GRANTS_DIR" => Path.expand("../config/capabilities", __DIR__),
      "EIGENFORGE_SIMULATOR_SNAPSHOTS_DIR" => Path.expand("../config/simulator_snapshots", __DIR__),
      "EIGENFORGE_IO_FAULT_STATUS_LOG" => Path.join(System.tmp_dir!(), "eigenforge-io-fault-status-test.log"),
      "EIGENFORGE_MAILBOX_RECEIPT_STORE_PATH" => Path.join(System.tmp_dir!(), "eigenforge-mailbox-receipts-test.json"),
      "EIGENFORGE_IO_COMMAND_STORE_PATH" => Path.join(System.tmp_dir!(), "eigenforge-io-command-store-test.json")
    }

  config :eigenforge_dashboard, Eigenforge.Dashboard.Endpoint,
    server: false

  config :eigenforge_mailbox,
    receipt_store_path: Path.join(System.tmp_dir!(), "eigenforge-mailbox-receipts-test.json")
end
