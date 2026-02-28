# Integration Boundaries

This library is focused on in-memory and file-backed document session
management. It intentionally excludes UI transport concerns.

## Core API boundaries

Use these modules as stable integration points:
- `Jido.Document`
- `Jido.Document.Agent`
- `Jido.Document.SessionRegistry`
- `Jido.Document.SignalBus`
- `Jido.Document.Document`
- `Jido.Document.Renderer`

## Session orchestration pattern

1. Start or resolve a session process:
   - Direct: `Jido.Document.start_session/1`
   - Registry-backed: `Jido.Document.SessionRegistry.ensure_session_by_path/3`
2. Execute commands through `Jido.Document.Agent.command/4`.
3. Subscribe for asynchronous updates through `Jido.Document.Agent.subscribe/2`.
4. Use lock APIs in `Jido.Document.SessionRegistry` for multi-client ownership.

## Filesystem and policy boundary

- Always pass `context_options: %{workspace_root: ...}` for load/save operations.
- Optional authorization policy can be supplied under
  `context_options: %{authorization: %{...}}`.

## Signals and event consumption

- Signal stream is session-scoped via `Jido.Document.SignalBus`.
- Consumers should treat payload as versioned contract from `Jido.Document.Signal`.
- For incident/debug workflows, export trace bundles with
  `Jido.Document.Agent.export_trace/2`.

## Release boundary

- Public semver-governed APIs: [`public-api.md`](./public-api.md)
- Compatibility guardrail snapshot: `priv/api/public_api_manifest.exs`
