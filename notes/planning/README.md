# Jido.Document Planning Index

This directory contains the phase-by-phase implementation plan for `Jido.Document`, an agent-oriented document editing system built on top of Jido.

## Phase Files
1. [Phase 1 - Foundation and Core Integration](./phase-01-foundation-and-core-integration.md): Establish project skeleton, runtime contracts, and dependency boundaries.
2. [Phase 2 - Document Model, Frontmatter, and Schema](./phase-02-document-model-frontmatter-schema.md): Implement core document representation, parsing, serialization, and schema validation.
3. [Phase 3 - Actions, Signals, and Agent Session Lifecycle](./phase-03-actions-signals-agent-session-lifecycle.md): Build action verbs, event contracts, and stateful session orchestration.
4. [Phase 4 - Markdown Rendering, Preview, and Change Propagation](./phase-04-markdown-rendering-preview-change-propagation.md): Deliver high-performance rendering and robust preview update flows.
5. [Phase 5 - Session Coordination and Concurrency Control](./phase-05-session-coordination-and-concurrency-control.md): Implement deterministic session discovery, ownership, and conflict control for core workflows.
6. [Phase 6 - Persistence, History, Versioning, and Recovery](./phase-06-persistence-history-versioning-recovery.md): Add safe persistence, undo/redo, revisioning, and crash recovery.
7. [Phase 7 - Governance, Security, and Operational Reliability](./phase-07-governance-security-operational-reliability.md): Harden access control, data safety, observability, and fault tolerance.
8. [Phase 8 - Release, Tooling, and Evolution](./phase-08-release-tooling-evolution.md): Finalize API stability, documentation, release automation, and extension roadmap.

## Shared Conventions
- Numbering:
  - Phases: `N`
  - Sections: `N.M`
  - Tasks: `N.M.K`
  - Subtasks: `N.M.K.L`
- Tracking:
  - Every phase, section, task, and subtask uses Markdown checkboxes (`[ ]`).
- Description requirement:
  - Every phase, section, and task starts with a `Description:` line.
- Integration-test requirement:
  - Each phase ends with a final Integration Tests section.

## Shared API / Interface Contract
- `Jido.Document.Document`:
  - `parse/2`, `serialize/1`, `validate/2`, `mark_dirty/1`
- `Jido.Document.Schema` and `Jido.Document.Field`:
  - Schema-driven field contracts for frontmatter rendering and validation.
- `Jido.Document.Actions.*`:
  - `Load`, `Save`, `UpdateFrontmatter`, `UpdateBody`, `Render`.
- `Jido.Document.Agent`:
  - Stateful session process coordinating actions, history, and signals.
- `Jido.Document.Renderer`:
  - Markdown-to-HTML/AST pipeline with diagnostics.
- `Jido.Document.Signal` event taxonomy:
  - `jido_document/document/loaded`, `updated`, `saved`, `rendered`, `failed`.
- `Jido.Document.SessionRegistry`:
  - Session lookup, ownership, and lifecycle coordination.

## Shared Assumptions and Defaults
- `jido`, `jido_action`, and `jido_signal` are used as orchestration and eventing primitives.
- `mdex` is the default markdown renderer.
- Frontmatter supports YAML (`---`) and TOML (`+++`) delimiters.
- API return pattern is `{:ok, value} | {:error, reason}`.
- Save path defaults to atomic writes with rollback-safe temporary files.
- Preview rendering defaults to async mode with debounce.

## Cross-Phase Acceptance Scenarios
- [x] X-1 Description: A document with schema-driven frontmatter can be loaded, edited concurrently by multiple clients, and saved without data loss.
- [x] X-2 Description: Concurrent updates from two clients resolve deterministically with explicit conflict signaling.
- [x] X-3 Description: Rendering failures degrade gracefully while preserving the last known good preview.
- [x] X-4 Description: Undo/redo remains coherent across frontmatter and body edits through save/reload cycles.
- [x] X-5 Description: External file mutations are detected and handled without silent overwrite.
- [x] X-6 Description: Unauthorized workspace or path access is rejected and fully audited.
- [x] X-7 Description: Crash/restart during autosave and render jobs recovers session state without corruption.
- [x] X-8 Description: Release artifacts, docs, and examples remain reproducible across supported Elixir/OTP versions.
