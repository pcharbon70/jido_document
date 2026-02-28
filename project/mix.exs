defmodule JidoDocument.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_document,
      version: "0.1.0",
      elixir: "~> 1.18",
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Document.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:stream_data, "~> 0.6", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      quality: [
        "cmd MIX_ENV=test mix format --check-formatted",
        "cmd MIX_ENV=test mix compile --warnings-as-errors",
        "cmd MIX_ENV=test mix jido.api_manifest --check",
        "cmd MIX_ENV=test mix test"
      ],
      ci: ["cmd MIX_ENV=test mix deps.get", "quality"]
    ]
  end

  defp description do
    "Session-oriented markdown and frontmatter document management with safety and reliability controls"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/pcharbon70/jido_document"
      },
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "docs",
        "priv/api/public_api_manifest.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/public-api.md",
        "docs/semver-policy.md",
        "docs/release-blocking-criteria.md",
        "docs/quickstart.md",
        "docs/integration-boundaries.md",
        "docs/troubleshooting.md"
      ]
    ]
  end
end
