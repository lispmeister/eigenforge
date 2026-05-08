defmodule Eigenforge.MixProject do
  use Mix.Project

  def project do
    [
      app: :eigenforge,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
