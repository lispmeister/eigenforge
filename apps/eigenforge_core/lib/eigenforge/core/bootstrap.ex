defmodule Eigenforge.Core.Bootstrap do
  @moduledoc """
  Startup validation for the local V1 runtime.

  This keeps the spec's fail-fast checks close to the runtime boundary: signed
  config must load, and any existing local ledger must still be compatible with
  the checked-in V1 payload and event versions before the supervised pipeline
  starts.
  """

  alias Eigenforge.Core.LedgerTooling
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.RuntimeConfig
  alias Eigenforge.Core.SignedConfig
  alias Eigenforge.Core.SimulatorFixture

  @type validation_result :: {:ok, %{active_room_id: String.t()}} | {:error, term()}

  @spec validate(RuntimeConfig.t()) :: validation_result()
  def validate(%RuntimeConfig{} = config) do
    with {:ok, %{active_room: %{"room_id" => room_id}}} <- SignedConfig.load_device_inventory(config),
         {:ok, _capability_grants} <- SignedConfig.load_capability_grants(config),
         :ok <- validate_simulator_fixtures(config),
         :ok <- prepare_ledger(config),
         :ok <- LedgerTooling.verify(config.core_db_path, config.core_node_id, config.hmac_secret) do
      {:ok, %{active_room_id: room_id}}
    end
  end

  defp validate_simulator_fixtures(%RuntimeConfig{io_mode: :simulator} = config) do
    SimulatorFixture.validate_directory(config.simulator_snapshots_dir)
  end

  defp validate_simulator_fixtures(%RuntimeConfig{}), do: :ok

  defp prepare_ledger(%RuntimeConfig{} = config) do
    with :ok <- LedgerSQLite.init(config.core_db_path, config.core_node_id),
         {:ok, [%{"count(*)" => count}]} <-
           LedgerSQLite.query_json(config.core_db_path, "SELECT count(*) FROM ledger_events;") do
      if count == 0 do
        LedgerTooling.ensure_genesis(config.core_db_path, config.core_node_id, config.hmac_secret)
      else
        :ok
      end
    end
  end
end
