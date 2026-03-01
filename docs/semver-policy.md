# Semantic Versioning Policy

`jido_document` follows Semantic Versioning (`MAJOR.MINOR.PATCH`).

Compatibility guarantees:
- `PATCH`: bug fixes and internal improvements only; no public API or behavior breaks.
- `MINOR`: additive, backward-compatible public API changes.
- `MAJOR`: breaking changes to public APIs or compatibility contracts.

Public API scope:
- Stable API is defined in [public-api.md](./public-api.md).
- Snapshot contract is stored at `priv/api/public_api_manifest.exs`.
- CI checks block releases when the API snapshot changes without explicit review.

Deprecation windows:
- Deprecations are introduced in a `MINOR` release.
- Deprecated APIs remain available for at least one subsequent `MINOR` release.
- Removal happens only in a `MAJOR` release.

Release notes requirements:
- Every release includes migration notes for compatibility-relevant changes.
- Breaking changes must include replacement guidance and rollback notes.
