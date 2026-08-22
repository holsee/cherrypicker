defmodule Cherrypicker.MixProject do
  use Mix.Project

  @version "0.1.1"
  @repo "https://github.com/holsee/cherrypicker"

  def project do
    [
      app: :cherrypicker,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Cherrypicker.CLI],
      package: package(),
      docs: [
        main: "readme",
        logo: "assets/logo-exdoc.png",
        extras: ["README.md", "DESIGN.md", "CHANGELOG.md"],
        source_ref: "v#{@version}"
      ],
      source_url: @repo,
      description:
        "Stable named .localhost URLs for local dev servers. " <>
          "A pure-BEAM reverse proxy and route registry: no Node, no npm, no root CA.",
      aliases: [
        precommit: [
          "compile --warnings-as-errors",
          "format --check-formatted",
          "credo --strict",
          "test"
        ]
      ]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {Cherrypicker.Application, []}
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.8"},
      {:finch, "~> 0.20"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT", "Apache-2.0"],
      links: %{
        "GitHub" => @repo,
        "Website" => "https://holsee.github.io/cherrypicker/"
      }
    ]
  end
end
