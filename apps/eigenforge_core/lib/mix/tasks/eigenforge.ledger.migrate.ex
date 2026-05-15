defmodule Mix.Tasks.Eigenforge.Ledger.Migrate do
  use Mix.Task

  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.RuntimeConfig

  @shortdoc "Validates the V1 ledger migration boundary"

  @impl true
  def run(args) do
    config = load_runtime!()
    %{from: from, to: to} = parse_args!(args)

    if from == 1 and to == 1 do
      case verify_v1_ledger(config.core_db_path) do
        :ok -> :ok
        {:error, reason} -> Mix.raise("ledger migrate failed: #{inspect(reason)}")
      end
    else
      Mix.raise("no V1→VN migration defined")
    end
  end

  defp verify_v1_ledger(db_path) do
    case LedgerSQLite.query_json(
           db_path,
           """
           SELECT sequence, json_extract(payload, '$.schema_version') AS schema_version
           FROM ledger_events
           ORDER BY sequence ASC;
           """
         ) do
      {:ok, rows} ->
        case Enum.find(rows, fn row -> row["schema_version"] != 1 end) do
          nil -> :ok
          row -> {:error, {:invalid_schema_version, row["sequence"], row["schema_version"]}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_args!(args) do
    case OptionParser.parse(args, strict: [from: :integer, to: :integer]) do
      {opts, [], []} -> %{from: Keyword.get(opts, :from), to: Keyword.get(opts, :to)}
      _ -> Mix.raise("invalid migrate arguments: expected --from and --to")
    end
  end

  defp load_runtime! do
    case RuntimeConfig.load() do
      {:ok, config} -> config
      {:error, errors} -> Mix.raise("invalid runtime config: #{inspect(errors)}")
    end
  end
end
