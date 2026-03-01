defmodule JidoDocument.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :jido_document,
      version: @version,
      elixir: "~> 1.18",
      source_url: "https://github.com/pcharbon70/jido_document",
      homepage_url: "https://github.com/pcharbon70/jido_document",
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
      name: "jido_document",
      maintainers: ["Pascal Charbonneau"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/pcharbon70/jido_document"
      },
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "docs",
        "priv/api/public_api_manifest.exs",
        "priv/migration/templates"
      ]
    ]
  end

  defp docs do
    [
      main: "Jido.Document",
      source_ref: "v#{@version}",
      source_url: "https://github.com/pcharbon70/jido_document",
      groups_for_extras: [
        "User Guides": ~r"docs/user/.*\\.md",
        "Developer Guides": ~r"docs/developer/.*\\.md"
      ],
      extras: [
        "README.md",
        "docs/public-api.md",
        "docs/semver-policy.md",
        "docs/release-blocking-criteria.md",
        "docs/quickstart.md",
        "docs/user/README.md",
        "docs/user/01-getting-started.md",
        "docs/user/02-document-structure-frontmatter-and-markdown.md",
        "docs/user/03-working-with-the-document-api.md",
        "docs/user/04-session-workflows-with-agent.md",
        "docs/user/05-rendering-and-preview-pipeline.md",
        "docs/user/06-concurrency-with-session-registry.md",
        "docs/user/07-history-checkpoints-and-safe-persistence.md",
        "docs/user/08-schema-validation-and-migration.md",
        "docs/developer/README.md",
        "docs/developer/01-architecture-overview.md",
        "docs/developer/02-supervision-and-runtime-topology.md",
        "docs/developer/03-agent-command-pipeline.md",
        "docs/developer/04-document-model-and-frontmatter-engine.md",
        "docs/developer/05-rendering-and-preview-subsystem.md",
        "docs/developer/06-persistence-divergence-and-recovery.md",
        "docs/developer/07-session-registry-locking-and-signals.md",
        "docs/developer/08-extension-points-and-api-evolution.md",
        "docs/integration-boundaries.md",
        "docs/troubleshooting.md",
        "docs/migration-guide.md",
        "docs/metadata-mapping-templates.md",
        "docs/plugin-api-lifecycle-policy.md",
        "docs/contribution-review-guidelines.md",
        "docs/architecture-review-cadence.md",
        "docs/post-release-verification.md"
      ]
    ]
  end
end
