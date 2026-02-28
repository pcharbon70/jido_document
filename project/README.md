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
