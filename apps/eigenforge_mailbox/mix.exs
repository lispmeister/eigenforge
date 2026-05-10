defmodule Eigenforge.Mailbox.MixProject do
  use Mix.Project

  def project do
    [
      app: :eigenforge_mailbox,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Eigenforge.Mailbox.Application, []}
    ]
  end

  defp deps do
    [
      {:eigenforge_contracts, in_umbrella: true}
    ]
  end
end
