# Public API

This document defines the semver-governed API surface for `jido_document`.

Stable modules:
- `Jido.Document`
- `Jido.Document.Agent`
- `Jido.Document.Document`
- `Jido.Document.Frontmatter`
- `Jido.Document.Renderer`
- `Jido.Document.SchemaMigration`
- `Jido.Document.SessionRegistry`
- `Jido.Document.Signal`
- `Jido.Document.SignalBus`

Internal modules:
- `Jido.Document.Action*`
- `Jido.Document.Actions*`
- `Jido.Document.Render.*`
- `Jido.Document.Persistence`
- `Jido.Document.History`
- `Jido.Document.Checkpoint`
- `Jido.Document.Revision`
- `Jido.Document.Authorization`
- `Jido.Document.Audit`
- `Jido.Document.Reliability`
- `Jido.Document.Safety`
- `Jido.Document.PathPolicy`
- `Jido.Document.PublicApi`

Deprecation policy:
- New deprecations must include a changelog note and migration guidance.
- Deprecations remain for at least one minor release before removal.
- Removals are only allowed in a new major release.
