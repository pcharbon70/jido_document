# Phase 4 - Markdown Rendering, Preview, and Change Propagation

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Document.Renderer`
- `Jido.Document.Actions.Render`
- `Jido.Document.Agent` preview state
- Signal `jido_document/document/rendered`

## Relevant Assumptions / Defaults
- `Mdex` is default renderer.
- Preview rendering is asynchronous with debounce.
- Renderer output includes diagnostics and table-of-contents data.

[x] 4 Phase 4 - Markdown Rendering, Preview, and Change Propagation  
Description: Deliver high-quality markdown rendering with performant, reliable preview update behavior.

 [x] 4.1 Section - Renderer Pipeline Foundation  
 Description: Build a configurable rendering pipeline with stable output contracts.

  [x] 4.1.1 Task - Implement `Jido.Document.Renderer` pipeline with `Mdex`  
  Description: Convert markdown body into HTML and structured preview artifacts.
   [x] 4.1.1.1 Subtask - Configure default markdown extensions and parsing options.  
   Description: Ensure predictable markdown feature support across adapters.
   [x] 4.1.1.2 Subtask - Integrate syntax-highlighting plugin path.  
   Description: Render fenced code blocks with configurable themes.
   [x] 4.1.1.3 Subtask - Exclude frontmatter from preview rendering.  
   Description: Keep metadata editing isolated from body presentation.

  [x] 4.1.2 Task - Define renderer output schema  
  Description: Standardize payload format for adapter consumption.
   [x] 4.1.2.1 Subtask - Include `html`, `toc`, and `diagnostics` fields.  
   Description: Provide full preview context to clients.
   [x] 4.1.2.2 Subtask - Add stable heading IDs and anchor metadata.  
   Description: Support deep-linking and synchronized navigation.
   [x] 4.1.2.3 Subtask - Add deterministic cache key generation.  
   Description: Enable render memoization without stale responses.

 [x] 4.2 Section - Incremental Rendering and Scheduling  
 Description: Keep previews responsive under frequent updates and large documents.

  [x] 4.2.1 Task - Implement incremental render decision logic  
  Description: Choose full or partial rerender paths based on change scope.
   [x] 4.2.1.1 Subtask - Track changed regions from body updates.  
   Description: Estimate impact on AST and preview output.
   [x] 4.2.1.2 Subtask - Define fallback threshold to full rerender.  
   Description: Avoid complex incremental logic for high-impact edits.
   [x] 4.2.1.3 Subtask - Record incremental-render effectiveness metrics.  
   Description: Measure whether optimization is worth retained complexity.

  [x] 4.2.2 Task - Implement render job queue and cancellation  
  Description: Prevent stale render work from flooding the system.
   [x] 4.2.2.1 Subtask - Add queue with bounded capacity and prioritization.  
   Description: Prefer latest edits over obsolete pending jobs.
   [x] 4.2.2.2 Subtask - Cancel superseded render jobs.  
   Description: Drop outdated jobs when newer revisions arrive.
   [x] 4.2.2.3 Subtask - Implement debounce/throttle controls.  
   Description: Balance responsiveness and CPU usage.

 [x] 4.3 Section - Diagnostics, Fallbacks, and Safety  
 Description: Ensure rendering failures are observable and user-safe.

  [x] 4.3.1 Task - Implement normalized render diagnostics  
  Description: Surface parser and rendering warnings/errors in a consistent structure.
   [x] 4.3.1.1 Subtask - Map renderer warnings to severity levels.  
   Description: Distinguish informational, warning, and blocking issues.
   [x] 4.3.1.2 Subtask - Include source locations where available.  
   Description: Help adapters highlight problematic ranges.
   [x] 4.3.1.3 Subtask - Attach remediation hints for common failures.  
   Description: Speed debugging for malformed markdown.

  [x] 4.3.2 Task - Implement fallback rendering strategy  
  Description: Maintain preview availability during renderer failure scenarios.
   [x] 4.3.2.1 Subtask - Keep and serve last known good preview.  
   Description: Avoid blank preview regressions on transient failures.
   [x] 4.3.2.2 Subtask - Add safe plain-markdown fallback output.  
   Description: Provide minimal preview for unsupported constructs.
   [x] 4.3.2.3 Subtask - Add failure event and recovery signals.  
   Description: Inform adapters when fallback mode is active.

 [x] 4.4 Section - Extensibility and Content Feature Support  
 Description: Prepare rendering pipeline for future plugin and feature growth.

  [x] 4.4.1 Task - Implement theme and code-language abstraction  
  Description: Support configurable syntax highlighting without tight coupling.
   [x] 4.4.1.1 Subtask - Add renderer theme registry abstraction.  
   Description: Allow theme switching by adapter or user setting.
   [x] 4.4.1.2 Subtask - Handle unsupported language identifiers.  
   Description: Fall back to plaintext rendering deterministically.
   [x] 4.4.1.3 Subtask - Add large code-block performance safeguards.  
   Description: Avoid pathological render latency on oversized snippets.

  [x] 4.4.2 Task - Implement plugin extension points  
  Description: Allow optional custom markdown transforms safely.
   [x] 4.4.2.1 Subtask - Define plugin registration and ordering rules.  
   Description: Keep plugin execution deterministic.
   [x] 4.4.2.2 Subtask - Isolate plugin failures from core rendering.  
   Description: Prevent one faulty plugin from crashing preview pipeline.
   [x] 4.4.2.3 Subtask - Add plugin compatibility checks at startup.  
   Description: Fail fast with diagnostics when plugin contracts mismatch.

 [x] 4.5 Section - Phase 4 Integration Tests  
 Description: Validate rendering quality, performance behavior, and fallback reliability.

  [x] 4.5.1 Task - Rendering pipeline integration tests  
  Description: Verify renderer output and diagnostics across markdown feature sets.
   [x] 4.5.1.1 Subtask - Test headings, links, lists, tables, and code blocks.  
   Description: Confirm expected HTML and TOC output.
   [x] 4.5.1.2 Subtask - Test malformed markdown diagnostics.  
   Description: Ensure warnings and errors are emitted consistently.
   [x] 4.5.1.3 Subtask - Test deterministic output for identical input.  
   Description: Guarantee stable previews and cache keys.

  [x] 4.5.2 Task - Scheduling and fallback integration tests  
  Description: Validate responsive behavior under rapid edit streams and failures.
   [x] 4.5.2.1 Subtask - Simulate bursty updates with queue saturation.  
   Description: Ensure stale jobs are canceled and latest preview wins.
   [x] 4.5.2.2 Subtask - Simulate renderer failure and fallback activation.  
   Description: Confirm last good preview remains available.
   [x] 4.5.2.3 Subtask - Simulate recovery from fallback mode.  
   Description: Ensure normal rendering resumes without restart.
