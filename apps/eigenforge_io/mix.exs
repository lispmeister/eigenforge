defmodule Eigenforge.IO.MixProject do
  use Mix.Project

  def project do
    [
      app: :eigenforge_io,
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
      extra_applications: [:logger, :inets, :ssl],
      mod: {Eigenforge.IO.Application, []}
    ]
  end

  defp deps do
    [
      {:eigenforge_contracts, in_umbrella: true},
      {:eigenforge_core, in_umbrella: true},
      {:websockex, "~> 0.5.1"}
    ]
  end
end
