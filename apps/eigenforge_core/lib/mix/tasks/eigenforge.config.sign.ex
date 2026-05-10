defmodule Mix.Tasks.Eigenforge.Config.Sign do
  use Mix.Task

  alias Eigenforge.Contracts
  alias Eigenforge.Core.DetachedSignature

  @shortdoc "Signs a detached V1 config payload and writes its .sig sidecar"

  @impl true
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [in: :string, sig: :string]
      )

    if invalid != [] do
      Mix.raise("unexpected arguments: #{inspect(invalid)}")
    end

    input_path = Keyword.get(opts, :in) || Mix.raise("--in is required")
    sig_path = Keyword.get(opts, :sig) || Mix.raise("--sig is required")

    payload =
      input_path
      |> File.read!()
      |> Contracts.decode_json!()
      |> DetachedSignature.validate_payload!()
      |> Contracts.signable_map()

    File.mkdir_p!(Path.dirname(sig_path))
    File.write!(sig_path, DetachedSignature.canonical_sidecar_json(payload, secret()) <> "\n")
  end

  defp secret do
    Application.fetch_env!(:eigenforge_core, :hmac_secret)
  end
end
