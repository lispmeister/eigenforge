defmodule Eigenforge.Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :eigenforge_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger],
      mod: {Eigenforge.Core.Application, []}
    ]
  end

  defp deps do
    [
      {:eigenforge_contracts, in_umbrella: true},
      {:eigenforge_mailbox, in_umbrella: true},
      {:exqlite, "~> 0.23"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
