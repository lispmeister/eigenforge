defmodule Mix.Tasks.Eigenforge.Ledger.Verify do
  use Mix.Task

  alias Eigenforge.Core.LedgerTooling
  alias Eigenforge.Core.RuntimeConfig

  @shortdoc "Verifies the local SQLite ledger hash chain and signatures"

  @impl true
  def run(_args) do
    config = load_runtime!()

    case LedgerTooling.verify(config.core_db_path, config.core_node_id, config.hmac_secret) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("ledger verify failed: #{inspect(reason)}")
    end
  end

  defp load_runtime! do
    case RuntimeConfig.load() do
      {:ok, config} -> config
      {:error, errors} -> Mix.raise("invalid runtime config: #{inspect(errors)}")
    end
  end
end
