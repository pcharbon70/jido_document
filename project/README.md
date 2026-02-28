# Jido.Document

`Jido.Document` provides in-memory and file-backed markdown/frontmatter document
session orchestration with safety, auditing, history, and recovery controls.

## Installation

```elixir
def deps do
  [
    {:jido_document, "~> 0.1"}
  ]
end
```

## Stable API and Release Policy

- Public API surface: [`docs/public-api.md`](./docs/public-api.md)
- Semantic versioning policy: [`docs/semver-policy.md`](./docs/semver-policy.md)
- Release gates: [`docs/release-blocking-criteria.md`](./docs/release-blocking-criteria.md)

## Guides and Examples

- Quickstart: [`docs/quickstart.md`](./docs/quickstart.md)
- Integration boundaries: [`docs/integration-boundaries.md`](./docs/integration-boundaries.md)
- Troubleshooting: [`docs/troubleshooting.md`](./docs/troubleshooting.md)
- Migration guide: [`docs/migration-guide.md`](./docs/migration-guide.md)
- Metadata mapping templates: [`docs/metadata-mapping-templates.md`](./docs/metadata-mapping-templates.md)
- Plugin API lifecycle policy: [`docs/plugin-api-lifecycle-policy.md`](./docs/plugin-api-lifecycle-policy.md)
- Contribution and review guidelines: [`docs/contribution-review-guidelines.md`](./docs/contribution-review-guidelines.md)
- Architecture review cadence: [`docs/architecture-review-cadence.md`](./docs/architecture-review-cadence.md)
- Post-release verification: [`docs/post-release-verification.md`](./docs/post-release-verification.md)
- Minimal sample: `mix run examples/minimal_api_sample.exs`
- Session concurrency sample: `mix run examples/session_concurrency_sample.exs`
- Crash recovery sample: `mix run examples/crash_recovery_sample.exs`

## API Contract Snapshot

Generate or update snapshot:

```bash
mix jido.api_manifest
```

Validate snapshot:

```bash
mix jido.api_manifest --check
```

## Migration Tooling

List bundled templates:

```bash
mix jido.migrate_docs --list-templates
```

Dry-run migration:

```bash
mix jido.migrate_docs --source ./content --template blog_frontmatter
```

Generate release-feedback triage report:

```bash
mix jido.triage_report --input ./issues.exs --output ./triage.md --min-score 20
```
