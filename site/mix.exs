defmodule CherrypickerSite.MixProject do
  use Mix.Project

  def project do
    [
      app: :cherrypicker_site,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: false,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:cherry, "~> 0.2.0"}
    ]
  end
end
