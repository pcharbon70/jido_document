# 05 - Rendering and Preview Subsystem

Rendering is split between orchestration and transformation components:

- orchestration:
  - `Jido.Document.Actions.Render`
  - `Jido.Document.Render.ChangeTracker`
  - `Jido.Document.Render.JobQueue`
  - `Jido.Document.Render.Metrics`
- transformation:
  - `Jido.Document.Renderer`
  - `Jido.Document.Render.PluginManager`
  - `Jido.Document.Render.ThemeRegistry`

## Render flow

```mermaid
flowchart TD
  Cmd["Agent command(:render)"] --> Decision["ChangeTracker.plan/3"]
  Decision --> Safety["Safety.scan + Safety.redact"]
  Safety --> Mode{"async?"}
  Mode -- "yes" --> Queue["JobQueue.enqueue/6"]
  Mode -- "no" --> Render["Renderer.render/2"]
  Render --> Plugins["PluginManager.apply_plugins/3"]
  Render --> Adapter["Adapter selection (:mdex/:simple/:auto)"]
  Adapter --> Preview["Preview payload"]
  Preview --> Metrics["Render.Metrics"]
```

## Renderer design points

- Frontmatter stripping is default for preview.
- Adapter auto-fallback:
  - prefers `:mdex` when available
  - falls back to `:simple` with diagnostics
- Fallback preview exists for degraded render conditions.

## Plugin model

- Contract:
  - `c:Jido.Document.Render.Plugin.transform/2`
  - `c:Jido.Document.Render.Plugin.compatible?/1`
- Manager behavior:
  - ordered execution by priority
  - startup compatibility checks
  - failure isolation with diagnostics, not hard crash

## Output contract

Render output includes:

- `html`
- `toc`
- `diagnostics`
- `cache_key`
- `adapter`
- `metadata` (extensions, syntax highlight settings, plugin list, etc.)
