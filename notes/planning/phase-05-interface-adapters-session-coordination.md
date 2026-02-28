# Phase 5 - Interface Adapters and Session Coordination

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoDocs.SessionRegistry`
- `JidoDocs.Agent`
- Signal subscription APIs
- LiveView/TUI/Desktop transport adapters

## Relevant Assumptions / Defaults
- Multiple adapters can connect to one session.
- Agent remains the canonical state owner.
- Adapters are thin clients over action and signal contracts.

[x] 5 Phase 5 - Interface Adapters and Session Coordination  
Description: Connect LiveView, TUI, and Desktop clients to shared session agents with deterministic synchronization.

 [x] 5.1 Section - Session Registry and Ownership Model  
 Description: Implement process discovery, ownership, and concurrent client coordination.

  [x] 5.1.1 Task - Implement session registry and lookup APIs  
  Description: Provide robust create/get/list lifecycle for session processes.
   [x] 5.1.1.1 Subtask - Add stable session ID generation strategy.  
   Description: Ensure deterministic mapping for file-backed sessions.
   [x] 5.1.1.2 Subtask - Support explicit and lazy session creation.  
   Description: Create sessions on demand with default or provided config.
   [x] 5.1.1.3 Subtask - Add stale session cleanup policies.  
   Description: Reclaim idle processes safely.

  [x] 5.1.2 Task - Implement ownership and locking semantics  
  Description: Avoid conflicting write operations across adapters.
   [x] 5.1.2.1 Subtask - Add optimistic lock token support.  
   Description: Detect stale client writes deterministically.
   [x] 5.1.2.2 Subtask - Add lock conflict response contract.  
   Description: Provide actionable conflict diagnostics to adapters.
   [x] 5.1.2.3 Subtask - Add administrative takeover path.  
   Description: Allow controlled override for stuck sessions.

 [x] 5.2 Section - LiveView Adapter  
 Description: Provide a first-class Phoenix LiveView integration path.

  [x] 5.2.1 Task - Implement LiveView command and event bridge  
  Description: Map LiveView events to actions and signals to assigns updates.
   [x] 5.2.1.1 Subtask - Implement mount/connect session bootstrap.  
   Description: Initialize or attach to session by file path/session ID.
   [x] 5.2.1.2 Subtask - Forward form and textarea change events.  
   Description: Route frontmatter/body updates via agent commands.
   [x] 5.2.1.3 Subtask - Subscribe and map signals to assigns.  
   Description: Keep UI state synchronized with agent state.

  [x] 5.2.2 Task - Implement schema-driven frontmatter form generation  
  Description: Build dynamic forms from `JidoDocs.Schema` definitions.
   [x] 5.2.2.1 Subtask - Map field types to LiveView form components.  
   Description: Support booleans, arrays, enums, and text values.
   [x] 5.2.2.2 Subtask - Render inline validation errors and hints.  
   Description: Display field-path diagnostics from schema validation.
   [x] 5.2.2.3 Subtask - Add dirty/saving state indicators.  
   Description: Reflect session state transitions in UI controls.

 [x] 5.3 Section - TUI Adapter  
 Description: Enable terminal-native workflows with low-latency synchronization.

  [x] 5.3.1 Task - Implement TUI command mapping and event loop integration  
  Description: Route keyboard commands to session actions and updates.
   [x] 5.3.1.1 Subtask - Define keybinding-to-action map.  
   Description: Support load, update, save, undo, and preview refresh controls.
   [x] 5.3.1.2 Subtask - Implement split-pane edit/preview model.  
   Description: Synchronize content and rendered output in terminal layouts.
   [x] 5.3.1.3 Subtask - Implement signal-driven status bar updates.  
   Description: Show session revision, save state, and errors.

  [x] 5.3.2 Task - Implement TUI resilience and accessibility controls  
  Description: Handle constrained terminals and unstable transport links.
   [x] 5.3.2.1 Subtask - Add redraw throttling and viewport optimization.  
   Description: Avoid flicker and excess CPU in rapid update flows.
   [x] 5.3.2.2 Subtask - Add low-color and narrow-width fallback layouts.  
   Description: Preserve usability under limited terminal capabilities.
   [x] 5.3.2.3 Subtask - Add disconnect/reconnect handling.  
   Description: Recover session linkage without data loss.

 [x] 5.4 Section - Desktop Adapter  
 Description: Expose robust IPC integration for desktop clients.

  [x] 5.4.1 Task - Implement desktop IPC command and event contracts  
  Description: Define stable transport payloads for session operations.
   [x] 5.4.1.1 Subtask - Define IPC message schemas for action requests.  
   Description: Standardize serialization and validation at boundaries.
   [x] 5.4.1.2 Subtask - Define event channel payloads for signals.  
   Description: Broadcast updates and diagnostics with revision metadata.
   [x] 5.4.1.3 Subtask - Add reconnect and replay strategy.  
   Description: Restore client state after process or transport interruption.

  [x] 5.4.2 Task - Implement multi-window coordination behavior  
  Description: Ensure predictable state sharing across desktop windows.
   [x] 5.4.2.1 Subtask - Support shared-session and isolated-session modes.  
   Description: Allow per-window configuration for collaboration style.
   [x] 5.4.2.2 Subtask - Broadcast lock/ownership changes across windows.  
   Description: Keep write permissions visible and synchronized.
   [x] 5.4.2.3 Subtask - Prompt conflict resolution on simultaneous edits.  
   Description: Prevent silent overwrite in multi-window scenarios.

 [x] 5.5 Section - Phase 5 Integration Tests  
 Description: Validate cross-adapter session consistency and conflict behavior.

  [x] 5.5.1 Task - Adapter consistency integration tests  
  Description: Ensure all adapters observe and apply the same session state changes.
   [x] 5.5.1.1 Subtask - Simulate LiveView and TUI connected to one session.  
   Description: Verify signal fanout and consistent revision updates.
   [x] 5.5.1.2 Subtask - Simulate Desktop multi-window shared session.  
   Description: Verify ownership and lock state propagation.
   [x] 5.5.1.3 Subtask - Verify adapter-specific diagnostics mapping.  
   Description: Ensure errors appear correctly in each interface.

  [x] 5.5.2 Task - Conflict and recovery integration tests  
  Description: Validate deterministic behavior under concurrent adapter writes.
   [x] 5.5.2.1 Subtask - Simulate stale lock token submissions.  
   Description: Assert conflict response contract and no silent overwrite.
   [x] 5.5.2.2 Subtask - Simulate adapter disconnect during save/render.  
   Description: Ensure reconnect can recover latest session snapshot.
   [x] 5.5.2.3 Subtask - Simulate forced ownership takeover.  
   Description: Validate auditability and predictable conflict resolution flow.
