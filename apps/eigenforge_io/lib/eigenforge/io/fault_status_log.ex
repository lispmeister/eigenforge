defmodule Eigenforge.IO.FaultStatusLog do
  @moduledoc """
  Writes the IO fault/status debug log.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Core.Redaction

  @spec append(map(), keyword()) :: :ok | {:error, term()}
  def append(event, opts \\ []) when is_map(event) do
    log_path = Keyword.fetch!(opts, :log_path)
    redactions = Keyword.get(opts, :redactions, [])

    payload =
      event
      |> Contracts.signable_map()
      |> Redaction.redact(secrets: redactions)
      |> Contracts.canonical_json()

    case File.mkdir_p(Path.dirname(log_path)) do
      :ok -> File.write(log_path, payload <> "\n", [:append])
      {:error, reason} -> {:error, reason}
    end
  end
end
