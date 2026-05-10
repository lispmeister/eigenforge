defmodule Mix.Tasks.Eigenforge.Ledger.Genesis do
  use Mix.Task

  alias Eigenforge.Core.LedgerTooling
  alias Eigenforge.Core.RuntimeConfig

  @shortdoc "Initializes the local SQLite ledger with a genesis row"

  @impl true
  def run(_args) do
    config = load_runtime!()

    case LedgerTooling.ensure_genesis(config.core_db_path, config.core_node_id, config.hmac_secret) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("ledger genesis failed: #{inspect(reason)}")
    end
  end

  defp load_runtime! do
    case RuntimeConfig.load() do
      {:ok, config} -> config
      {:error, errors} -> Mix.raise("invalid runtime config: #{inspect(errors)}")
    end
  end
end
