# Phase 6 - Persistence, History, Versioning, and Recovery

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Document.Actions.Save`
- `Jido.Document.Agent` history state
- `Jido.Document.Document` revision metadata
- Autosave/checkpoint configuration

## Relevant Assumptions / Defaults
- Saves should be atomic and crash-safe.
- Undo/redo must work across frontmatter and body mutations.
- External file mutation detection is required before overwrite.

[ ] 6 Phase 6 - Persistence, History, Versioning, and Recovery  
Description: Deliver durable persistence semantics, coherent edit history, and robust crash recovery.

 [x] 6.1 Section - Save Semantics and Filesystem Safety  
 Description: Implement reliable write behavior and external mutation protection.

  [x] 6.1.1 Task - Implement atomic save pipeline  
  Description: Ensure writes are durable and rollback-safe across failures.
   [x] 6.1.1.1 Subtask - Write serialized output to temp file with fsync.  
   Description: Guarantee data durability before final rename.
   [x] 6.1.1.2 Subtask - Rename temp file atomically to target path.  
   Description: Prevent partially-written target files.
   [x] 6.1.1.3 Subtask - Preserve file mode/ownership metadata when possible.  
   Description: Avoid permission regressions on save.

  [x] 6.1.2 Task - Implement on-disk divergence detection  
  Description: Detect and handle external file edits before save.
   [x] 6.1.2.1 Subtask - Track baseline hash and mtime per session load.  
   Description: Compare state before committing writes.
   [x] 6.1.2.2 Subtask - Block unsafe overwrite when divergence detected.  
   Description: Return explicit conflict reason and remediation options.
   [x] 6.1.2.3 Subtask - Add merge strategy hook points.  
   Description: Allow custom conflict handlers by integration policy.

 [x] 6.2 Section - Undo/Redo History Model  
 Description: Preserve reversible edit operations with bounded resource usage.

  [x] 6.2.1 Task - Define history data model and limits  
  Description: Represent reversible operations and snapshots efficiently.
   [x] 6.2.1.1 Subtask - Choose operation-log vs snapshot hybrid strategy.  
   Description: Balance memory cost and replay speed.
   [x] 6.2.1.2 Subtask - Define bounded history retention policy.  
   Description: Cap memory usage without breaking expected UX.
   [x] 6.2.1.3 Subtask - Define branch behavior after undo + new edit.  
   Description: Ensure deterministic redo invalidation rules.

  [x] 6.2.2 Task - Implement undo/redo command handling  
  Description: Apply and reverse frontmatter/body operations reliably.
   [x] 6.2.2.1 Subtask - Implement reversible frontmatter operations.  
   Description: Support merge, replace, and key delete reversal.
   [x] 6.2.2.2 Subtask - Implement reversible body operations.  
   Description: Support patch-based and full-replacement reversal.
   [x] 6.2.2.3 Subtask - Emit history state signals.  
   Description: Inform subscribers when undo/redo availability changes.

 [x] 6.3 Section - Autosave and Checkpoint Recovery  
 Description: Minimize data loss from process crashes or interruptions.

  [x] 6.3.1 Task - Implement autosave checkpoint mechanism  
  Description: Persist session recovery state on configurable cadence and triggers.
   [x] 6.3.1.1 Subtask - Define checkpoint file format and location policy.  
   Description: Keep recovery artifacts discoverable and isolated.
   [x] 6.3.1.2 Subtask - Trigger checkpoints by timer and significant edits.  
   Description: Balance durability with write overhead.
   [x] 6.3.1.3 Subtask - Clean checkpoints after successful durable save.  
   Description: Avoid stale recovery artifacts.

  [x] 6.3.2 Task - Implement crash/restart recovery flow  
  Description: Restore unsaved edits safely when sessions restart.
   [x] 6.3.2.1 Subtask - Detect orphan checkpoints on startup.  
   Description: Surface pending recovery candidates.
   [x] 6.3.2.2 Subtask - Provide recover/discard decision API.  
   Description: Let consumers drive explicit recovery choices.
   [x] 6.3.2.3 Subtask - Reconcile recovered state with current disk content.  
   Description: Prevent accidental loss when disk changed after crash.

 [x] 6.4 Section - Revisioning and Schema Evolution  
 Description: Track document evolution and support metadata model changes safely.

  [x] 6.4.1 Task - Implement revision metadata strategy  
  Description: Assign stable revision identifiers and provenance metadata.
   [x] 6.4.1.1 Subtask - Generate monotonic revision identifiers per session.  
   Description: Enable deterministic ordering for updates and signals.
   [x] 6.4.1.2 Subtask - Attach actor/source metadata to revisions.  
   Description: Improve traceability across integration sources.
   [x] 6.4.1.3 Subtask - Persist revision metadata in save outputs or sidecars.  
   Description: Support long-running audit and merge workflows.

  [x] 6.4.2 Task - Implement schema evolution/migration helpers  
  Description: Migrate frontmatter fields as schemas evolve between versions.
   [x] 6.4.2.1 Subtask - Add field rename/coercion migration primitives.  
   Description: Handle common schema drift scenarios.
   [x] 6.4.2.2 Subtask - Implement migration dry-run reporting.  
   Description: Show proposed changes before applying transformations.
   [x] 6.4.2.3 Subtask - Add irreversible-change safety guards.  
   Description: Require explicit confirmation for destructive migrations.

 [ ] 6.5 Section - Phase 6 Integration Tests  
 Description: Validate persistence safety, history coherence, and recovery workflows.

  [ ] 6.5.1 Task - Persistence and divergence integration tests  
  Description: Ensure save pipeline and conflict detection behave safely.
   [ ] 6.5.1.1 Subtask - Simulate write interruption during save.  
   Description: Confirm target file remains uncorrupted.
   [ ] 6.5.1.2 Subtask - Simulate external file modification before save.  
   Description: Assert overwrite prevention and conflict diagnostics.
   [ ] 6.5.1.3 Subtask - Validate permission and metadata preservation.  
   Description: Confirm save keeps expected file properties.

  [ ] 6.5.2 Task - History and recovery integration tests  
  Description: Confirm undo/redo and checkpoint recovery across realistic edit sessions.
   [ ] 6.5.2.1 Subtask - Test mixed frontmatter/body undo/redo chains.  
   Description: Verify state and revision correctness after multiple reversals.
   [ ] 6.5.2.2 Subtask - Test crash and checkpoint recovery flow.  
   Description: Ensure unsaved edits can be restored deterministically.
   [ ] 6.5.2.3 Subtask - Test recovery when disk state diverged.  
   Description: Verify explicit reconciliation path and no silent loss.
