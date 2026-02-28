# Phase 3 - Actions, Signals, and Agent Session Lifecycle

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoDocs.Actions.Load`
- `JidoDocs.Actions.Save`
- `JidoDocs.Actions.UpdateFrontmatter`
- `JidoDocs.Actions.UpdateBody`
- `JidoDocs.Actions.Render`
- `JidoDocs.Agent`
- Jido signal contracts

## Relevant Assumptions / Defaults
- Actions are atomic and composable.
- Signals are the primary synchronization channel to UI adapters.
- Agent is the source of truth for in-session document state.

[ ] 3 Phase 3 - Actions, Signals, and Agent Session Lifecycle  
Description: Build atomic operation verbs, stable event contracts, and reliable session orchestration.

 [x] 3.1 Section - Action Contracts and Error Taxonomy  
 Description: Define consistent action input/output and failure semantics.

  [x] 3.1.1 Task - Standardize action behavior contract  
  Description: Ensure all actions follow a predictable callable shape and metadata model.
   [x] 3.1.1.1 Subtask - Define input schema pattern for actions.  
   Description: Include `session_id`, `path`, `document`, and request-scoped options.
   [x] 3.1.1.2 Subtask - Define return contract and telemetry fields.  
   Description: Include correlation IDs and durations for each action call.
   [x] 3.1.1.3 Subtask - Define idempotency expectations by action type.  
   Description: Clarify safe retry behavior for load/save/render operations.

  [x] 3.1.2 Task - Implement domain error taxonomy  
  Description: Normalize parser, validation, filesystem, and render failures.
   [x] 3.1.2.1 Subtask - Define canonical reason codes.  
   Description: Map failures to stable machine-readable atoms.
   [x] 3.1.2.2 Subtask - Attach human-readable diagnostics.  
   Description: Include context that adapters can display directly.
   [x] 3.1.2.3 Subtask - Build error conversion helpers.  
   Description: Translate upstream exceptions into domain errors.

 [ ] 3.2 Section - Core Document Actions  
 Description: Implement file and mutation actions that enforce document invariants.

  [ ] 3.2.1 Task - Implement `Load` and `Save` actions  
  Description: Support robust document I/O for session lifecycle.
   [ ] 3.2.1.1 Subtask - Implement secure path resolution on load.  
   Description: Enforce workspace and traversal constraints.
   [ ] 3.2.1.2 Subtask - Implement save with serialization and write safety hooks.  
   Description: Integrate document serialization and error normalization.
   [ ] 3.2.1.3 Subtask - Emit structured action metadata.  
   Description: Capture bytes, duration, and revision in results.

  [ ] 3.2.2 Task - Implement update and render action flows  
  Description: Support frontmatter/body mutation and preview generation operations.
   [ ] 3.2.2.1 Subtask - Implement `UpdateFrontmatter` with schema validation.  
   Description: Apply merge/replace semantics and return updated document state.
   [ ] 3.2.2.2 Subtask - Implement `UpdateBody` with revision tracking.  
   Description: Preserve change metadata for history and undo.
   [ ] 3.2.2.3 Subtask - Implement `Render` action integration.  
   Description: Return HTML/TOC/diagnostics payloads for preview updates.

 [ ] 3.3 Section - Signal Taxonomy and Subscription Model  
 Description: Define and implement predictable event fanout for UI synchronization.

  [ ] 3.3.1 Task - Define signal types and payload schemas  
  Description: Ensure adapters can reliably consume session events.
   [ ] 3.3.1.1 Subtask - Define loaded/updated/saved/rendered/failed event shapes.  
   Description: Include document revision and session identifiers.
   [ ] 3.3.1.2 Subtask - Version event payload schema.  
   Description: Allow backward-compatible event evolution.
   [ ] 3.3.1.3 Subtask - Define payload size and truncation policy.  
   Description: Prevent oversized event messages from destabilizing transports.

  [ ] 3.3.2 Task - Implement subscription lifecycle and fanout behavior  
  Description: Manage subscribers, backpressure, and cleanup.
   [ ] 3.3.2.1 Subtask - Implement scoped topics by session.  
   Description: Isolate event streams across concurrent sessions.
   [ ] 3.3.2.2 Subtask - Implement backpressure and dropped-event policy.  
   Description: Define best-effort vs guaranteed delivery tradeoffs.
   [ ] 3.3.2.3 Subtask - Implement dead-subscriber cleanup.  
   Description: Remove stale listeners and report cleanup events.

 [ ] 3.4 Section - Agent State and Session Lifecycle  
 Description: Build a resilient stateful session process that orchestrates actions and events.

  [ ] 3.4.1 Task - Implement `JidoDocs.Agent` state model and initialization  
  Description: Represent active document session state with history and preview metadata.
   [ ] 3.4.1.1 Subtask - Define state fields (`document`, `preview`, `history`, `subscribers`, `locks`).  
   Description: Support editing, rendering, and multi-adapter coordination.
   [ ] 3.4.1.2 Subtask - Implement init and optional auto-load flow.  
   Description: Allow session boot from empty or file-backed states.
   [ ] 3.4.1.3 Subtask - Implement graceful termination behavior.  
   Description: Flush checkpoints and emit session-closed signal.

  [ ] 3.4.2 Task - Implement command handling and orchestration logic  
  Description: Sequence actions safely under concurrent edits and render requests.
   [ ] 3.4.2.1 Subtask - Implement synchronous vs asynchronous command routing.  
   Description: Keep UI responsiveness while protecting data integrity.
   [ ] 3.4.2.2 Subtask - Add concurrency guards around save/render/update overlap.  
   Description: Prevent stale writes and out-of-order preview states.
   [ ] 3.4.2.3 Subtask - Add optimistic-update rollback strategy.  
   Description: Reconcile failed actions without corrupting session state.

 [ ] 3.5 Section - Phase 3 Integration Tests  
 Description: Validate action orchestration, signal delivery, and session lifecycle behavior.

  [ ] 3.5.1 Task - Action and signal integration tests  
  Description: Confirm that action execution emits expected event sequences.
   [ ] 3.5.1.1 Subtask - Verify load/update/save signal order.  
   Description: Ensure deterministic events for adapter consumers.
   [ ] 3.5.1.2 Subtask - Verify failed action event payloads.  
   Description: Confirm diagnostic completeness and reason codes.
   [ ] 3.5.1.3 Subtask - Verify event schema version consistency.  
   Description: Ensure adapters can parse expected payload versions.

  [ ] 3.5.2 Task - Session lifecycle and concurrency tests  
  Description: Validate behavior under parallel edits and process restarts.
   [ ] 3.5.2.1 Subtask - Simulate concurrent frontmatter/body updates.  
   Description: Confirm conflict resolution and revision integrity.
   [ ] 3.5.2.2 Subtask - Simulate save/render overlap under load.  
   Description: Ensure no stale preview overwrite occurs.
   [ ] 3.5.2.3 Subtask - Simulate crash/restart of agent process.  
   Description: Verify predictable recovery and signal continuity.
