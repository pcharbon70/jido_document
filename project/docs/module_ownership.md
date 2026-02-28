# JidoDocs Module Ownership

This document defines ownership boundaries established in Phase 1.

## Top-level ownership
- `JidoDocs`: public facade and external API boundary.
- `JidoDocs.Document`: canonical document data model.
- `JidoDocs.Agent`: stateful session process ownership.
- `JidoDocs.Config`: runtime configuration schema and normalization.

## Namespace ownership
- `JidoDocs.Actions.*`: atomic operation boundaries (`Load`, `Save`, `Render`, updates).
- `JidoDocs.Schema`: frontmatter schema behavior contract.
- `JidoDocs.Renderer`: markdown rendering boundary and output contract.
- `JidoDocs.Transport`: adapter boundary for LiveView, TUI, and Desktop.

## Supervision ownership
- `JidoDocs.Application`: application startup and top-level supervision.
- `JidoDocs.SessionRegistry`: process discovery and session lifecycle supervision.
