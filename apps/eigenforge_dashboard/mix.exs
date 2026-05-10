defmodule Eigenforge.Dashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :eigenforge_dashboard,
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
      mod: {Eigenforge.Dashboard.Application, []}
    ]
  end

  defp deps do
    [
      {:eigenforge_contracts, in_umbrella: true},
      {:eigenforge_core, in_umbrella: true}
    ]
  end
end
