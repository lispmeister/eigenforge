defmodule Eigenforge.Contracts.MixProject do
  use Mix.Project

  def project do
    [
      app: :eigenforge_contracts,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger],
      mod: {Eigenforge.Contracts.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
