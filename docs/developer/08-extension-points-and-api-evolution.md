# 08 - Extension Points and API Evolution

This guide covers where the system is intentionally extensible and how API
stability is enforced across releases.

## Primary extension points

### Action modules

- Contract: `Jido.Document.Action` behavior
- Requirements:
  - `name/0`
  - `idempotency/0`
  - `run/2`
- Execution harness provides:
  - context normalization
  - authorization integration
  - telemetry
  - canonical result wrapping

### Render plugins

- Contract: `Jido.Document.Render.Plugin`
  - `transform/2`
  - `compatible?/1`
- Runtime:
  - configured plugin list
  - startup compatibility checks
  - isolated plugin failure diagnostics

### Migration templates

- Built-in template directory:
  - `priv/migration/templates/*.exs`
- Runtime tooling:
  - `Jido.Document.Migrator`
  - `mix jido.migrate_docs`

## Stability and release controls

- Stable API manifest:
  - `Jido.Document.PublicApi`
  - `priv/api/public_api_manifest.exs`
- Semver governance:
  - [`../semver-policy.md`](../semver-policy.md)
- Release gating:
  - [`../release-blocking-criteria.md`](../release-blocking-criteria.md)

## Quality controls in repo

- CI alias:
  - `mix ci` -> format, compile warnings-as-errors, API manifest check, tests
- Integration-heavy regression coverage:
  - `test/jido/document/*integration_test.exs`
- Property coverage:
  - `property_document_roundtrip_test.exs`

## Change strategy for maintainers

1. Update docs and contracts first.
2. Keep stable public API backward compatible for minor releases.
3. Add migration notes before deprecation.
4. Use manifest checks to detect accidental API drift.
