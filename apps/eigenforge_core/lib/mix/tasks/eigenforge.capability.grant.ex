defmodule Mix.Tasks.Eigenforge.Capability.Grant do
  use Mix.Task

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CapabilityGrant
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.DetachedSignature

  @shortdoc "Creates a signed V1 capability grant JSON file and .sig sidecar"

  @impl true
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          subject: :string,
          target: :string,
          action: :string,
          scope: :string,
          out: :string,
          sig: :string
        ]
      )

    if invalid != [] do
      Mix.raise("unexpected arguments: #{inspect(invalid)}")
    end

    subject = Keyword.get(opts, :subject) || Mix.raise("--subject is required")
    target = Keyword.get(opts, :target) || Mix.raise("--target is required")
    action = Keyword.get(opts, :action) || Mix.raise("--action is required")
    scope = Keyword.get(opts, :scope) || Mix.raise("--scope is required")
    out_path = Keyword.get(opts, :out) || Mix.raise("--out is required")
    sig_path = Keyword.get(opts, :sig) || Mix.raise("--sig is required")

    grant =
      CapabilityGrant.new!(%{
        grant_id: grant_id(subject, target, action, scope),
        subject: subject,
        target: target,
        action: action,
        scope: scope,
        issued_at: now()
      })

    payload = Contracts.signable_map(grant)

    File.mkdir_p!(Path.dirname(out_path))
    File.mkdir_p!(Path.dirname(sig_path))
    File.write!(out_path, Contracts.canonical_json(payload) <> "\n")
    File.write!(sig_path, DetachedSignature.canonical_sidecar_json(payload, secret()) <> "\n")
  end

  defp now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> CanonicalTime.format()
  end

  defp secret do
    Application.fetch_env!(:eigenforge_core, :hmac_secret)
  end

  defp grant_id(subject, target, action, scope) do
    [
      "cap",
      subject,
      target,
      action,
      scope
    ]
    |> Enum.join("-")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
