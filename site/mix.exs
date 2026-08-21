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
      # Pinned past hex 0.2.0 for the dep-site overlay fix (cherry#86);
      # return to {:cherry, "~> 0.2.1"} at the next cherry release.
      {:cherry, github: "holsee/cherry", ref: "36bf79c"}
    ]
  end
end
