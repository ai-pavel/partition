defmodule KVStore.MixProject do
  use Mix.Project

  def project do
    [
      app: :kvstore,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [threshold: 0]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {KVStore.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:plug_cowboy, "~> 2.6"},
      {:jason, "~> 1.4"},
      {:merkle_map, "~> 0.2", optional: true}
    ]
  end
end
