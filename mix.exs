defmodule LoggerFileBackendWin.Mixfile do
  use Mix.Project

  @version "0.0.1"

  def project do
    [
      app: :logger_file_backend_win,
      version: @version,
      elixir: "~> 1.0",
      description: description(),
      package: package(),
      deps: deps(),
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        source_url: "https://github.com/simonmcconnell/logger_file_backend_win",
        extras: ["README.md", "CHANGELOG.md"]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp description do
    "Simple logger backend that writes to a file (for Windows)"
  end

  defp package do
    [
      maintainers: ["Simon McConnell"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/simonmcconnell/logger_file_backend_win"},
      files: [
        "lib",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test]},
      {:ex_doc, "~> 0.26", only: :dev}
    ]
  end
end
